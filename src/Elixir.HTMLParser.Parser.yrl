Nonterminals
  element
  children
.

Terminals
  tag_open
  tag_open_close
  tag_close
  text
.

Rootsymbol children.

element -> tag_open_close : format_tag('$1', []).
element -> tag_open tag_close : format_tag('$1', []).
element -> tag_open children tag_close : format_tag('$1', '$2').
element -> text : element(3, '$1').

children -> element : ['$1'].
children -> element children : ['$1' | '$2'].

Erlang code.

format_tag({_, _, {Name, Attrs}}, Children) ->
  {Name, Attrs, Children}.
