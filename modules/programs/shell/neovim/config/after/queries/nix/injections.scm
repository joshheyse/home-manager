; extends

; Inject nginx into Nix strings with # nginx comment
((indented_string_expression
  (string_fragment) @injection.content
  (#match? @injection.content "^[ \t\n]*#[ \t]*nginx"))
 (#set! injection.language "nginx"))

; Inject sql into Nix strings with # sql comment
((indented_string_expression
  (string_fragment) @injection.content
  (#match? @injection.content "^[ \t\n]*#[ \t]*sql"))
 (#set! injection.language "sql"))

; Inject bash into Nix strings with # bash comment
((indented_string_expression
  (string_fragment) @injection.content
  (#match? @injection.content "^[ \t\n]*#[ \t]*bash"))
 (#set! injection.language "bash"))
