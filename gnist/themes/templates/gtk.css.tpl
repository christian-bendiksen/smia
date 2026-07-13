@define-color background     {{ background }};
@define-color foreground     {{ foreground }};
@define-color accent_bg_color {{ accent }};
@define-color accent_fg_color @background;

@define-color color0         {{ color0 }};
@define-color color1         {{ color1 }};
@define-color color2         {{ color2 }};
@define-color color3         {{ color3 }};
@define-color color4         {{ color4 }};
@define-color color5         {{ color5 }};
@define-color color6         {{ color6 }};
@define-color color7         {{ color7 }};
@define-color color8         {{ color8 }};
@define-color color9         {{ color9 }};
@define-color color10        {{ color10 }};
@define-color color11        {{ color11 }};
@define-color color12        {{ color12 }};
@define-color color13        {{ color13 }};
@define-color color14        {{ color14 }};
@define-color color15        {{ color15 }};

@define-color blue_1   @color12;
@define-color blue_2   @color12;
@define-color blue_3   @color4;
@define-color blue_4   @color4;
@define-color blue_5   @color4;

@define-color green_1  @color10;
@define-color green_2  @color10;
@define-color green_3  @color2;
@define-color green_4  @color2;
@define-color green_5  @color2;

@define-color yellow_1 @color11;
@define-color yellow_2 @color11;
@define-color yellow_3 @color3;
@define-color yellow_4 @color3;
@define-color yellow_5 @color3;

@define-color orange_1 @color11;
@define-color orange_2 @color11;
@define-color orange_3 @color3;
@define-color orange_4 @color3;
@define-color orange_5 @color3;

@define-color red_1    @color9;
@define-color red_2    @color9;
@define-color red_3    @color1;
@define-color red_4    @color1;
@define-color red_5    @color1;

@define-color purple_1 @color13;
@define-color purple_2 @color13;
@define-color purple_3 @color5;
@define-color purple_4 @color5;
@define-color purple_5 @color5;

@define-color brown_1  @color3;
@define-color brown_2  @color3;
@define-color brown_3  @color3;
@define-color brown_4  @color3;
@define-color brown_5  @color3;

@define-color light_1  @color15;
@define-color light_2  @color15;
@define-color light_3  @color7;
@define-color light_4  @color7;
@define-color light_5  @color7;

@define-color dark_1   @color8;
@define-color dark_2   @color8;
@define-color dark_3   @color0;
@define-color dark_4   @color0;
@define-color dark_5   @color0;

@define-color destructive_bg_color @red_3;
@define-color destructive_fg_color @background;

@define-color success_bg_color @green_4;
@define-color success_fg_color @background;

@define-color warning_bg_color @yellow_5;
@define-color warning_fg_color @background;

@define-color error_bg_color @red_3;
@define-color error_fg_color @background;

@define-color accent_color @accent_bg_color;
@define-color destructive_color @destructive_bg_color;
@define-color success_color @success_bg_color;
@define-color warning_color @warning_bg_color;
@define-color error_color @error_bg_color;

@define-color window_bg_color @background;
@define-color window_fg_color @foreground;

@define-color view_bg_color @background;
@define-color view_fg_color @foreground;

@define-color headerbar_bg_color @background;
@define-color headerbar_fg_color @foreground;
@define-color headerbar_border_color @foreground;
@define-color headerbar_backdrop_color @background;

@define-color headerbar_shade_color alpha(@background, 0.07);
@define-color headerbar_darker_shade_color alpha(@background, 0.12);

@define-color sidebar_bg_color @background;
@define-color sidebar_fg_color @foreground;
@define-color sidebar_backdrop_color @background;
@define-color sidebar_shade_color alpha(@background, 0.07);
@define-color sidebar_border_color alpha(@color8, 0.30);

@define-color secondary_sidebar_bg_color @background;
@define-color secondary_sidebar_fg_color @foreground;
@define-color secondary_sidebar_backdrop_color @background;
@define-color secondary_sidebar_shade_color alpha(@background, 0.07);
@define-color secondary_sidebar_border_color alpha(@color8, 0.30);

@define-color card_bg_color @background;
@define-color card_fg_color @foreground;
@define-color card_shade_color alpha(@background, 0.07);

@define-color dialog_bg_color @background;
@define-color dialog_fg_color @foreground;

@define-color popover_bg_color @background;
@define-color popover_fg_color @foreground;
@define-color popover_shade_color alpha(@background, 0.07);

@define-color thumbnail_bg_color @background;
@define-color thumbnail_fg_color @foreground;

@define-color shade_color alpha(@background, 0.07);
@define-color scrollbar_outline_color alpha(@foreground, 0.25);

@define-color theme_bg_color @window_bg_color;
@define-color theme_fg_color @window_fg_color;

@define-color theme_base_color @view_bg_color;
@define-color theme_text_color @view_fg_color;

@define-color theme_selected_bg_color @accent_bg_color;
@define-color theme_selected_fg_color @accent_fg_color;

@define-color insensitive_bg_color color-mix(in srgb, @window_bg_color 60%, @view_bg_color);
@define-color insensitive_fg_color color-mix(in srgb, @window_fg_color 50%, transparent);
@define-color insensitive_base_color @view_bg_color;

@define-color borders color-mix(in srgb, currentColor 15%, transparent);
@media (prefers-contrast: more) {
  @define-color borders color-mix(in srgb, currentColor 50%, transparent);
}

@define-color theme_unfocused_bg_color @window_bg_color;
@define-color theme_unfocused_fg_color @window_fg_color;

@define-color theme_unfocused_base_color @view_bg_color;
@define-color theme_unfocused_text_color @view_fg_color;

@define-color theme_unfocused_selected_bg_color @accent_bg_color;
@define-color theme_unfocused_selected_fg_color @accent_fg_color;

@define-color unfocused_insensitive_color @insensitive_bg_color;
@define-color unfocused_borders @borders;

:root {
  --accent-blue:   @color4;
  --accent-teal:   @color6;
  --accent-green:  @color2;
  --accent-yellow: @color3;
  --accent-orange: @color11;
  --accent-red:    @color1;
  --accent-pink:   @color13;
  --accent-purple: @color5;
  --accent-slate:  @color8;

  --accent-bg-color: @accent_bg_color;
  --accent-fg-color: @accent_fg_color;
  --accent-color: @accent_bg_color;

  --destructive-bg-color: @destructive_bg_color;
  --destructive-fg-color: @destructive_fg_color;
  --destructive-color:    @destructive_color;

  --success-bg-color: @success_bg_color;
  --success-fg-color: @success_fg_color;
  --success-color:    @success_color;

  --warning-bg-color: @warning_bg_color;
  --warning-fg-color: @warning_fg_color;
  --warning-color:    @warning_color;

  --error-bg-color: @error_bg_color;
  --error-fg-color: @error_fg_color;
  --error-color:    @error_color;

  --window-bg-color: @window_bg_color;
  --window-fg-color: @window_fg_color;

  --view-bg-color: @view_bg_color;
  --view-fg-color: @view_fg_color;

  --headerbar-bg-color: @headerbar_bg_color;
  --headerbar-fg-color: @headerbar_fg_color;
  --headerbar-border-color: @headerbar_border_color;
  --headerbar-backdrop-color: @headerbar_backdrop_color;
  --headerbar-shade-color: @headerbar_shade_color;
  --headerbar-darker-shade-color: @headerbar_darker_shade_color;

  --sidebar-bg-color: @sidebar_bg_color;
  --sidebar-fg-color: @sidebar_fg_color;
  --sidebar-backdrop-color: @sidebar_backdrop_color;
  --sidebar-border-color: @sidebar_border_color;
  --sidebar-shade-color: @sidebar_shade_color;

  --secondary-sidebar-bg-color: @secondary_sidebar_bg_color;
  --secondary-sidebar-fg-color: @secondary_sidebar_fg_color;
  --secondary-sidebar-backdrop-color: @secondary_sidebar_backdrop_color;
  --secondary-sidebar-border-color: @secondary_sidebar_border_color;
  --secondary-sidebar-shade-color: @secondary_sidebar_shade_color;

  --card-bg-color: @card_bg_color;
  --card-fg-color: @card_fg_color;
  --card-shade-color: @card_shade_color;

  --dialog-bg-color: @dialog_bg_color;
  --dialog-fg-color: @dialog_fg_color;

  --popover-bg-color: @popover_bg_color;
  --popover-fg-color: @popover_fg_color;
  --popover-shade-color: @popover_shade_color;

  --thumbnail-bg-color: @thumbnail_bg_color;
  --thumbnail-fg-color: @thumbnail_fg_color;

  --shade-color: @shade_color;
  --scrollbar-outline-color: @scrollbar_outline_color;

  --active-toggle-bg-color: @background;
  --active-toggle-fg-color: @foreground;

  --overview-bg-color: @background;
  --overview-fg-color: @foreground;

  --border-opacity: 15%;
  --dim-opacity: 55%;
  --disabled-opacity: 50%;
}

@media (prefers-contrast: more) {
  :root {
    --border-opacity: 50%;
    --dim-opacity: 90%;
    --disabled-opacity: 40%;
  }
}

.navigation-sidebar row:selected {
  background-color: @accent_bg_color;
  color: @accent_fg_color;
}
.navigation-sidebar row:hover:not(:selected) {
  background-color: alpha(@accent_bg_color, 0.18);
}

list.boxed-list {
  border: 1px solid alpha(@color8, 0.55);
  border-radius: 12px;
  background-image: none;
}
list.boxed-list > row + row {
  border-top: 1px solid alpha(@color8, 0.45);
}
list.boxed-list:backdrop > row + row {
  border-top-color: alpha(@color8, 0.32);
}

undershoot,
overshoot {
  background-image: none;
}
