#!/usr/bin/env python3
"""Jupyter kernel bridge daemon.

Connects to an existing Jupyter kernel via its connection file, reads code
from a named pipe (FIFO), executes on the kernel, and writes structured
JSON output to a regular file.

Usage:
    cell-bridge.py --runtime-dir /tmp/jupyter-bridge-XXXX --connection-file /path/to/kernel-xxx.json
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import signal
import sys
from pathlib import Path

from jupyter_client import BlockingKernelClient

logger = logging.getLogger("cell-bridge")


def setup_logging(log_file: Path) -> None:
    handler = logging.FileHandler(log_file)
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)


def collect_output(kc, msg_id: str) -> dict:  # noqa: ANN001
    """Collect iopub messages for a specific execution until idle."""
    outputs: list[dict] = []
    status = "ok"
    error = None
    execution_count = None

    while True:
        try:
            msg = kc.get_iopub_msg(timeout=120)
        except Exception:
            break

        # Only process messages from our execution
        if msg["parent_header"].get("msg_id") != msg_id:
            continue

        msg_type = msg["header"]["msg_type"]
        content = msg["content"]

        if msg_type == "status" and content.get("execution_state") == "idle":
            break
        elif msg_type == "stream":
            outputs.append(
                {"type": "stream", "name": content["name"], "text": content["text"]}
            )
        elif msg_type in ("execute_result", "display_data"):
            outputs.append({"type": msg_type, "data": content.get("data", {})})
            if msg_type == "execute_result":
                execution_count = content.get("execution_count")
        elif msg_type == "error":
            status = "error"
            error = {
                "ename": content["ename"],
                "evalue": content["evalue"],
                "traceback": content["traceback"],
            }
            outputs.append({"type": "error", **error})

    return {
        "status": status,
        "execution_count": execution_count,
        "outputs": outputs,
        "error": error,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Jupyter kernel bridge daemon")
    parser.add_argument("--runtime-dir", required=True, help="Runtime directory path")
    parser.add_argument(
        "--connection-file", required=True, help="Kernel connection file path"
    )
    args = parser.parse_args()

    runtime_dir = Path(args.runtime_dir)
    pipe_in = runtime_dir / "pipe.in"
    out_json = runtime_dir / "out.json"
    log_file = runtime_dir / "bridge.log"

    setup_logging(log_file)
    logger.info(
        "Starting cell-bridge with connection-file=%s", args.connection_file
    )

    # Connect to existing kernel
    kc = BlockingKernelClient()
    kc.load_connection_file(args.connection_file)
    kc.start_channels()
    kc.wait_for_ready(timeout=60)
    logger.info("Connected to kernel")

    def shutdown(signum, frame) -> None:  # noqa: ANN001
        logger.info("Shutting down (signal %s)", signum)
        kc.stop_channels()
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    # Main loop: read from FIFO, execute, write output
    while True:
        try:
            logger.info("Waiting for input on %s", pipe_in)
            with open(pipe_in) as f:
                code = f.read()

            if not code.strip():
                continue

            logger.info("Executing %d chars of code", len(code))
            msg_id = kc.execute(code)
            result = collect_output(kc, msg_id)
            logger.info("Execution complete: status=%s", result["status"])

            # Write output atomically
            tmp = out_json.with_suffix(".tmp")
            tmp.write_text(json.dumps(result, indent=2))
            os.replace(tmp, out_json)

        except Exception:
            logger.exception("Error in main loop")


if __name__ == "__main__":
    main()
