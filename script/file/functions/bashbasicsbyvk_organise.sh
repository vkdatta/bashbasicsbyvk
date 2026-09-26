_ts_to_ymd() {
local ts=$1
local days=$(( ts / 86400 ))
local z=$(( days + 719468 ))
local era=$(( (z >= 0 ? z : z - 146096) / 146097 ))
local doe=$(( z - era * 146097 ))
local yoe=$(( (doe - doe/1460 + doe/36524 - doe/146096) / 365 ))
local y=$(( yoe + era * 400 ))
local doy=$(( doe - (365*yoe + yoe/4 - yoe/100) ))
local mp=$(( (5*doy + 2) / 153 ))
local d=$(( doy - (153*mp + 2)/5 + 1 ))
local m=$(( mp + (mp < 10 ? 3 : -9) ))
[[ $m -le 2 ]] && y=$(( y + 1 ))
_YMD_Y=$y _YMD_M=$m _YMD_D=$d
}

_batch_stat() {
local p="$1"
declare -gA _FILE_TS=()
while IFS='|' read -r fname ts; do
[ -f "$fname" ] || continue
_FILE_TS["$fname"]=$ts
done < <(stat -c "%n|%Y" "$p"/* 2>/dev/null)
}

_flush_buckets() {
local -n _bkts="$1"
for dest in "${!_bkts[@]}"; do
mkdir -p "$dest"
local -a batch=()
while IFS= read -r item; do
[ -n "$item" ] && batch+=("$item")
done <<< "${_bkts[$dest]}"
[ ${#batch[@]} -gt 0 ] && mv "${batch[@]}" "$dest/"
done
}

organise_by_ext() {
echo "📁 Organise by extension:"
echo "1) All files by ext"
echo "2) Selected extension"
read -p "Choice: " ech
local -a files=()
for f in "$path"/*; do [ -f "$f" ] && files+=("$f"); done
[ ${#files[@]} -eq 0 ] && { echo "No files"; return; }
case "$ech" in
1)
declare -A ext_buckets=()
for f in "${files[@]}"; do
local b="${f##*/}"
local e="${b##*.}"
[ "$e" = "$b" ] && e="noext"
ext_buckets["$path/$e"]+="$f"$'\n'
done
_flush_buckets ext_buckets
;;
2)
read -p "Extension (e.g. py or .py): " inputext
local ext="${inputext#.}"
[ -z "$ext" ] && ext="noext"
local folder="$path/$ext"
local -a batch=()
if [ "$ext" = "noext" ]; then
for f in "${files[@]}"; do
local b="${f##*/}"; [[ "$b" != *.* ]] && batch+=("$f")
done
else
for f in "${files[@]}"; do
[[ "${f##*.}" == "$ext" ]] && batch+=("$f")
done
fi
if [ ${#batch[@]} -gt 0 ]; then
mkdir -p "$folder"
mv "${batch[@]}" "$folder/"
fi
;;
esac
echo "✅ Organised by extension"
}

organise_by_year() {
local -a files=()
for f in "$path"/*; do [ -f "$f" ] && files+=("$f"); done
[ ${#files[@]} -eq 0 ] && { echo "No files"; return; }
read -p "Number of years to group (1 = each year separate): " group_y
[[ $group_y =~ ^[0-9]+$ ]] || group_y=1
_batch_stat "$path"
local min_y=99999 max_y=0
for f in "${files[@]}"; do
_ts_to_ymd "${_FILE_TS[$f]:-0}"
(( _YMD_Y < min_y )) && min_y=$_YMD_Y
(( _YMD_Y > max_y )) && max_y=$_YMD_Y
done
declare -A buckets=()
for f in "${files[@]}"; do
_ts_to_ymd "${_FILE_TS[$f]:-0}"
local y=$_YMD_Y dest
if [ "$group_y" -eq 1 ]; then
dest="$path/$y"
else
local offset=$(( y - min_y ))
local gstart=$(( min_y + (offset / group_y) * group_y ))
local gend=$(( gstart + group_y - 1 ))
[ $gend -gt $max_y ] && gend=$max_y
dest="$path/${gstart}-${gend}/$y"
fi
buckets["$dest"]+="$f"$'\n'
done
_flush_buckets buckets
echo "✅ Organised by year(s)"
}

organise_by_year_month() {
local -a files=()
for f in "$path"/*; do [ -f "$f" ] && files+=("$f"); done
[ ${#files[@]} -eq 0 ] && { echo "No files"; return; }
read -p "Number of years to group: " group_y
[[ $group_y =~ ^[0-9]+$ ]] || group_y=1
read -p "Number of months to group: " group_m
[[ $group_m =~ ^[0-9]+$ ]] || group_m=1
_batch_stat "$path"
local month_abbr=(jan feb mar apr may jun jul aug sep oct nov dec)
local min_y=99999 max_y=0
for f in "${files[@]}"; do
_ts_to_ymd "${_FILE_TS[$f]:-0}"
(( _YMD_Y < min_y )) && min_y=$_YMD_Y
(( _YMD_Y > max_y )) && max_y=$_YMD_Y
done
declare -A buckets=()
for f in "${files[@]}"; do
_ts_to_ymd "${_FILE_TS[$f]:-0}"
local y=$_YMD_Y m=$_YMD_M
local year_dest
if [ "$group_y" -eq 1 ]; then
year_dest="$path/$y"
else
local offset=$(( y - min_y ))
local gstart=$(( min_y + (offset / group_y) * group_y ))
local gend=$(( gstart + group_y - 1 ))
[ $gend -gt $max_y ] && gend=$max_y
year_dest="$path/${gstart}-${gend}/$y"
fi
local mname="${month_abbr[$((m-1))]}"
local dest
if [ "$group_m" -eq 1 ]; then
dest="$year_dest/$mname"
else
local mgi=$(( (m-1) / group_m ))
local mstart=$(( mgi * group_m + 1 ))
local mend=$(( mstart + group_m - 1 ))
[ $mend -gt 12 ] && mend=12
dest="$year_dest/${month_abbr[$((mstart-1))]}-${month_abbr[$((mend-1))]}/$mname"
fi
buckets["$dest"]+="$f"$'\n'
done
_flush_buckets buckets
echo "✅ Organised by year(s) > month(s)"
}

organise_by_year_month_date() {
local -a files=()
for f in "$path"/*; do [ -f "$f" ] && files+=("$f"); done
[ ${#files[@]} -eq 0 ] && { echo "No files"; return; }
read -p "Number of years to group: " group_y
[[ $group_y =~ ^[0-9]+$ ]] || group_y=1
read -p "Number of months to group: " group_m
[[ $group_m =~ ^[0-9]+$ ]] || group_m=1
read -p "Number of days to group: " group_d
[[ $group_d =~ ^[0-9]+$ ]] || group_d=1
_batch_stat "$path"
local month_abbr=(jan feb mar apr may jun jul aug sep oct nov dec)
local min_y=99999 max_y=0
for f in "${files[@]}"; do
_ts_to_ymd "${_FILE_TS[$f]:-0}"
(( _YMD_Y < min_y )) && min_y=$_YMD_Y
(( _YMD_Y > max_y )) && max_y=$_YMD_Y
done
declare -A buckets=()
for f in "${files[@]}"; do
_ts_to_ymd "${_FILE_TS[$f]:-0}"
local y=$_YMD_Y m=$_YMD_M d=$_YMD_D
local year_dest
if [ "$group_y" -eq 1 ]; then
year_dest="$path/$y"
else
local offset=$(( y - min_y ))
local gstart=$(( min_y + (offset / group_y) * group_y ))
local gend=$(( gstart + group_y - 1 ))
[ $gend -gt $max_y ] && gend=$max_y
year_dest="$path/${gstart}-${gend}/$y"
fi
local mname="${month_abbr[$((m-1))]}"
local month_dest
if [ "$group_m" -eq 1 ]; then
month_dest="$year_dest/$mname"
else
local mgi=$(( (m-1) / group_m ))
local mstart=$(( mgi * group_m + 1 ))
local mend=$(( mstart + group_m - 1 ))
[ $mend -gt 12 ] && mend=12
month_dest="$year_dest/${month_abbr[$((mstart-1))]}-${month_abbr[$((mend-1))]}/$mname"
fi
local dest
if [ "$group_d" -eq 1 ]; then
dest="$month_dest/$d"
else
local dgi=$(( (d-1) / group_d ))
local dstart=$(( dgi * group_d + 1 ))
local dend=$(( dstart + group_d - 1 ))
[ $dend -gt 31 ] && dend=31
dest="$month_dest/${dstart}-${dend}/$d"
fi
buckets["$dest"]+="$f"$'\n'
done
_flush_buckets buckets
echo "✅ Organised by year(s) > month(s) > date(s)"
}

unorganise() {
echo "🔄 Unorganise and bring to current location:"
echo "1) Unorganise all"
echo "2) Unorganise selected folders"
read -p "Choice: " uch
if [ "$uch" = "1" ]; then
find "$path" -mindepth 2 -type f -exec mv -t "$path/" {} +
find "$path" -mindepth 1 -type d -empty -delete
echo "✅ All files brought to current location. Empty folders removed."
else
if select_items_common "UNORGANISE (folders only)"; then
for dir in "${selected_items[@]}"; do
[ -d "$dir" ] || continue
find "$dir" -type f -exec mv -t "$path/" {} +
find "$dir" -type d -empty -delete
done
echo "✅ Selected folders unorganised."
fi
fi
}

organise_by_az() {
local -a items=()
for f in "$path"/*; do [ -e "$f" ] && items+=("$f"); done
[ ${#items[@]} -eq 0 ] && { echo "No items"; return; }
declare -A az_buckets=()
declare -A new_dirs=()
for f in "${items[@]}"; do
local b="${f##*/}"
local first="${b:0:1}"
local key
# normalise to uppercase for A-Z, keep digits/symbols as-is
if [[ "$first" =~ [a-zA-Z] ]]; then
key="${first^^}"
elif [[ "$first" =~ [0-9] ]]; then
key="$first"
else
key="#"
fi
local dest="$path/$key"
new_dirs["$dest"]=1
az_buckets["$dest"]+="$f"$'\n'
done
# remove entries that would move a folder into itself
for dest in "${!az_buckets[@]}"; do
[ -d "$dest" ] && [ "${new_dirs[$dest]+_}" ] && {
# strip that entry out — it's a pre-existing folder matching a key
local cleaned=""
while IFS= read -r item; do
[ "$item" = "$dest" ] && continue
[ -n "$item" ] && cleaned+="$item"$'\n'
done <<< "${az_buckets[$dest]}"
az_buckets["$dest"]="$cleaned"
}
done
_flush_buckets az_buckets
echo "✅ Organised A-Z"
}

organise_menu() {
echo "🗂️ Organise files in current location ($path):"
echo "1) Organise by ext"
echo "2) Organise by year(s) (metadata)"
echo "3) Organise by year(s) > month(s) (metadata)"
echo "4) Organise by year(s) > month(s) > date(s) (metadata)"
echo "5) Unorganise and bring it to current location"
echo "6) Organise A-Z"
read -p "Enter choice [1-6]: " och
case "$och" in
1) organise_by_ext ;;
2) organise_by_year ;;
3) organise_by_year_month ;;
4) organise_by_year_month_date ;;
5) unorganise ;;
6) organise_by_az ;;
*) echo "❌ Invalid choice" ;;
esac
}
