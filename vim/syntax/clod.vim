" Vim syntax file for ClodLang (.clod files)
" ClodMUD database format with CoffeeScript method bodies

if exists("b:current_syntax")
  finish
endif

" Load CoffeeScript syntax as base
runtime! syntax/coffee.vim
unlet! b:current_syntax

" ClodLang structural keywords (at start of line)
syn match clodObject      "^\s*object\>"
syn match clodMethod      "^\s*method\>"
syn match clodParent      "^\s*parent\>"
syn match clodName        "^\s*name\>"
syn match clodDefaultPar  "^\s*default_parent\>"

" ClodLang method directives (indented, at start of line content)
syn match clodUsing       "^\s\+using\>"
syn match clodArgs        "^\s\+args\>"
syn match clodVars        "^\s\+vars\>"
syn match clodDisallow    "^\s\+disallow\s\+overrides\>"

" Object references: $name and #id
syn match clodObjRef      "\$\w\+"
syn match clodIdRef       "#\d\+"

" Link to highlight groups
hi def link clodObject      Structure
hi def link clodMethod      Function
hi def link clodParent      Type
hi def link clodName        Identifier
hi def link clodDefaultPar  Type

hi def link clodUsing       PreProc
hi def link clodArgs        PreProc
hi def link clodVars        PreProc
hi def link clodDisallow    PreProc

hi def link clodObjRef      Special
hi def link clodIdRef       Number

let b:current_syntax = "clod"
