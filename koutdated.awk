
function ord(c,  i) {
  for (i = 1; i <= 26; i++) if (substr("abcdefghijklmnopqrstuvwxyz", i, 1) == c) return i
  for (i = 1; i <= 10; i++) if (substr("0123456789", i, 1) == c) return 27 + i
  return 38
}

function ftype(c) { return (c ~ /[0-9]/) ? 1 : 2 }

# runtype: 1 = digit run, 2 = letter run, 0 = absent field.  Ordering used
# when two versions differ in field count: digits(1) > absent(0) > letters(2)
# so 1.0.1 > 1.0 > 1.0rc1 and 1.0.1 > 1.0rc1.
function runtype(s) {
  if (s == "") return 0
  return ftype(substr(s, 1, 1))
}
function vpush(list, n, cap) {
  n++
  while (n <= cap) {
    list[n] = (n <= 6 ? 0 : -2)
    n++
  }
  return n
}

# vcmp(a, b) -> -1 a older, 0 equal, 1 a newer
# rank: digits(1) -> 3, absent -> 2, letters -> 1
function rank(t) { return (t == 1 ? 3 : t == 0 ? 2 : 1) }

# vcmp(a, b) -> 1 if a is newer, -1 if older, 0 if equivalent
function vcmp(a, b,  pa, pb, na, nb, i, ca, cb, ra, rb, sa, sb, la, lb, j) {
  na = split(vnorm(a), pa, /\./)
  nb = split(vnorm(b), pb, /\./)
  for (i = 1; i <= 8; i++) {
    ca = (i <= na ? pa[i] : "")
    cb = (i <= nb ? pb[i] : "")
    if (ca == cb) continue
    ra = rank(runtype(ca))
    rb = rank(runtype(cb))
    if (ra != rb) return (ra > rb ? 1 : -1)
    if (runtype(ca) == 1) {
      # both digit runs: longer (after stripping zeros) wins, else lex
      sa = ca
      sb = cb
      gsub(/^0+/, "", sa)
      gsub(/^0+/, "", sb)
      la = length(sa)
      lb = length(sb)
      if (la != lb) return (la > lb ? 1 : -1)
      if (sa != sb) return (sa > sb ? 1 : -1)
      continue
    }
    # both letter runs (mixed alphanumeric falls back to plain string
    # ordering, which is fine for the suffixes we actually ship)
    if (ca !~ /^[a-z]*$/ || cb !~ /^[a-z]*$/) return (ca > cb ? 1 : -1)
    la = length(ca)
    lb = length(cb)
    j = (la < lb ? la : lb)
    while (j > 0) {
      if (ord(substr(ca, j, 1)) != ord(substr(cb, j, 1)))
        return (ord(substr(ca, j, 1)) > ord(substr(cb, j, 1)) ? 1 : -1)
      j--
    }
    if (la != lb) return (la > lb ? 1 : -1)
  }
  return 0
}

# vnorm: lower case, drop a leading v, turn - + ~ _ into dots and
# split runs at digit/letter boundaries so 1.0beta2 becomes 1.0.beta.2
function vnorm(s,  out, i, c, p, t, n) {
  s = tolower(s)
  sub(/^v/, "", s)
  gsub(/[-+~_]/, ".", s)
  out = ""
  p = ""
  n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    t = "o"
    if (c ~ /[0-9]/) t = "d"
    else if (c ~ /[a-z]/) t = "a"
    if (t == "d" && p == "a") out = out "."
    if (t == "a" && p == "d") out = out "."
    out = out c
    if (t != "o") p = t
  }
  return out
}
BEGIN { FS = "	"; OFS = "	"; nof = split(advisory, adva, /[ ,]/) }

# pass 1: remote.vers
FNR == NR {
  if (NF < 3) next
  ref = $3
  if (($1 SUBSEP $2) in seen) next
  seen[$1 SUBSEP $2] = 1
  cnt[$1]++
  R[$1, cnt[$1]] = $2
  RR[$1, cnt[$1]] = $3
  next
}

# pass 2: local.vers
{
  name = $1
  lver = $2
  cat = $3
  n = cnt[name] + 0
  if (n == 0) { print "S", name, lver; next }
  best = ""
  bestref = ""
  for (i = 1; i <= n; i++) {
    rv = R[name, i]
    rf = RR[name, i]
    ref = rf
    isadv = 0
    for (j = 1; j <= nof; j++) if (adva[j] != "" && index(rf, adva[j]) == 1) isadv = 1
    if (isadv) { print "A", name, lver, rv, rf, "advisory-ref"; continue }
    if (rv == lver) continue
    t = rv
    sub(/^v/, "", t)
    if (t == lver) { print "A", name, lver, rv, rf, "v-prefix"; continue }
    if (index(rv, lver "-") == 1 || index(rv, lver "+") == 1) { print "A", name, lver, rv, rf, "distro-suffix"; continue }
    if (index(lver, rv "-") == 1 || index(lver, rv "+") == 1) { print "A", name, lver, rv, rf, "ours-patched"; continue }
    if (vcmp(rv, lver) <= 0) { old[name] = old[name] " " ref "=" rv; continue }
    if (best == "" || vcmp(rv, best) > 0) { best = rv; bestref = rf }
  }
  if (best != "") print "C", name, lver, best, bestref, cat
  else if (old[name] != "") print "A", name, lver, "", "", "behind-us:" old[name]
}
