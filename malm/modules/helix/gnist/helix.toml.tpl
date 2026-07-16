"ui.background"                    = { bg = "background" }
"ui.background.separator"          = { fg = "color8" }

"ui.text"                          = { fg = "color7" }
"ui.text.focus"                    = { fg = "color11", modifiers = ["bold"] }

"ui.linenr"                        = { fg = "color4" }
"ui.linenr.selected"               = { fg = "color7", modifiers = ["bold"] }

"ui.cursor"                        = { modifiers = ["reversed"] }
"ui.cursor.primary"                = { modifiers = ["reversed"] }
"ui.cursor.secondary"              = { modifiers = ["reversed"] }
"ui.cursor.match"                  = { fg = "color3", underline = { color = "color3", style = "line" } }

"ui.cursorline.primary"            = { bg = "color8" }
"ui.cursorline.secondary"          = { bg = "color8" }

"ui.selection"                     = { bg = "color8" }
"ui.selection.primary"             = { fg = "selection_foreground", bg = "selection_background" }

"ui.statusline"                    = { fg = "color7", bg = "color8" }
"ui.statusline.inactive"           = { fg = "color5", bg = "color8" }
"ui.statusline.normal"             = { fg = "color0", bg = "accent" }
"ui.statusline.insert"             = { fg = "color0", bg = "color2" }
"ui.statusline.select"             = { fg = "color0", bg = "color4" }
"ui.statusline.separator"          = { fg = "color8" }

"ui.popup"                         = { fg = "color7", bg = "color8" }
"ui.popup.info"                    = { fg = "color7", bg = "color8" }
"ui.window"                        = { fg = "color4" }
"ui.help"                          = { fg = "color7", bg = "color8" }

"ui.menu"                          = { fg = "color7", bg = "color8" }
"ui.menu.selected"                 = { fg = "color0", bg = "accent" }
"ui.menu.scroll"                   = { fg = "color5", bg = "color8" }

"ui.gutter"                        = { fg = "color8" }
"ui.virtual.ruler"                 = { bg = "color8" }
"ui.virtual.whitespace"            = { fg = "color4" }
"ui.virtual.indent-guide"          = { fg = "color4" }
"ui.virtual.wrap"                  = { fg = "color4" }

"ui.virtual.inlay-hint"            = { fg = "color5", bg = "color8" }
"ui.virtual.inlay-hint.parameter"  = { fg = "color5", bg = "color8" }
"ui.virtual.inlay-hint.type"       = { fg = "color5", bg = "color8" }

"ui.virtual.jump-label"            = { fg = "color3", modifiers = ["bold", "underlined"] }

"comment"                          = { fg = "color5", modifiers = ["italic"] }

"variable"                         = { fg = "color7" }
"variable.other.member"            = { fg = "color6" }

"constant"                         = { fg = "color3" }
"constant.numeric"                 = { fg = "color3" }
"constant.character.escape"        = { fg = "color14" }

"string"                           = { fg = "color2" }

"type"                             = { fg = "color11" }
"attribute"                        = { fg = "color4" }

"function"                         = { fg = "color12" }
"constructor"                      = { fg = "color12" }
"special"                          = { fg = "color6" }

"keyword"                          = { fg = "color13" }
"label"                            = { fg = "color13" }
"namespace"                        = { fg = "color5" }

"operator"                         = { fg = "color5" }
"punctuation"                      = { fg = "color5" }

"markup.heading"                   = { fg = "color11", modifiers = ["bold"] }
"markup.list"                      = { fg = "color3" }
"markup.bold"                      = { fg = "color11", modifiers = ["bold"] }
"markup.italic"                    = { fg = "color5", modifiers = ["italic"] }
"markup.strikethrough"             = { modifiers = ["crossed_out"] }

"markup.link.url"                  = { fg = "color3", underline = { color = "color3", style = "line" } }
"markup.link.text"                 = { fg = "color2" }

"markup.quote"                     = { fg = "color6" }
"markup.raw"                       = { fg = "color2" }

"diff.plus"                        = { fg = "color2" }
"diff.minus"                       = { fg = "color1" }
"diff.delta"                       = { fg = "color6" }
"diff.delta.moved"                 = { fg = "color4" }

"warning"                          = { fg = "color3" }
"error"                            = { fg = "color1" }
"info"                             = { fg = "color6" }
"hint"                             = { fg = "color5" }

"diagnostic.warning"               = { underline = { color = "color3", style = "curl" } }
"diagnostic.error"                 = { underline = { color = "color1", style = "curl" } }
"diagnostic.info"                  = { underline = { color = "color6", style = "dotted" } }
"diagnostic.hint"                  = { underline = { color = "color5", style = "double_line" } }

[palette]
background           = "{{ background }}"
foreground           = "{{ foreground }}"
accent               = "{{ accent }}"
selection_foreground = "{{ selection_foreground }}"
selection_background = "{{ selection_background }}"

color0  = "{{ color0 }}"
color1  = "{{ color1 }}"
color2  = "{{ color2 }}"
color3  = "{{ color3 }}"
color4  = "{{ color4 }}"
color5  = "{{ color5 }}"
color6  = "{{ color6 }}"
color7  = "{{ color7 }}"
color8  = "{{ color8 }}"
color9  = "{{ color9 }}"
color10 = "{{ color10 }}"
color11 = "{{ color11 }}"
color12 = "{{ color12 }}"
color13 = "{{ color13 }}"
color14 = "{{ color14 }}"
color15 = "{{ color15 }}"
