commas() {
  awk -v number="$1" 'BEGIN {
    digits = sprintf("%d", number)
    sign = ""
    if (substr(digits, 1, 1) == "-") { sign = "-"; digits = substr(digits, 2) }
    grouped = ""
    while (length(digits) > 3) {
      grouped = "," substr(digits, length(digits) - 2) grouped
      digits = substr(digits, 1, length(digits) - 3)
    }
    printf "%s%s%s", sign, digits, grouped
  }'
}