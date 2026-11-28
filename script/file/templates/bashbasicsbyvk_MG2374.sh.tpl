# MG2374 — PICK SCREEN: "<icon> Select <what> <job_word> <job>"  (default 🛷 Select Items for Transfer · delete: 🚮 Select extensions to delete)
# Pick screens: Transfer source / destination, the csv file picker, the fx item picker, the delete-by-group pickers, a results screen.
# No title block when {what} is empty (a results screen names itself in the nav path).
$menu_header

?what {icon} Select {what} {job_word} {job}
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
