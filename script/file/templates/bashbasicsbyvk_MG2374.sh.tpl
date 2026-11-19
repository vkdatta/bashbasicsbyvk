# MG2374 — PICK SCREEN: "Select <what> for <job>" (Transfer source / destination, the csv file picker, the fx item picker, a results screen).
# No title block when {what} is empty (a results screen names itself in the nav path).
$menu_header

?what 🛷 Select {what} for {job}
?what
?what {pick_note}
{cd_path}
{nav_path}

$menu_body
{file_list}

$menu_footer

{footer_commands}
{menu_suggestions}
{footer_acceptor}
