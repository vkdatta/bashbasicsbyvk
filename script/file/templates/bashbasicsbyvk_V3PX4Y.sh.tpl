# V3PX4Y — TABBED MENU: every _tm_define screen (rules, sw, upgrade, fx, rb, cs, github tags ...)
# title, the tab bar, the words about the tab, the count row, then the screen's own rows (menu_description) and the filter row.
# tab_gap = the blank row before menu_description (a screen sets it empty to drop it).
$menu_header

{menu_name}

{tab_bar}

{tab_description}
{count_line}
?tab_gap
{menu_description}
{filter_line}

$menu_body
{menu_list}

$menu_footer
{footer_commands}
{menu_suggestions}
{footer_acceptor}
