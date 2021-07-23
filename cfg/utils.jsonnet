// fixme: many/all of these probably could get lifted to wct/cfg/

{
    // Return true if string s has at least one % symbol.
    haspct(s, pct="%"):: std.length(std.findSubstr(pct, s))>0,

    // append a suffix to the base name of a file name, prior to .ext
    basename_append(filename, suffix) :: {
        local l = std.split(filename, "."),
        ret:"%s%s.%s"%[l[0], suffix, l[1]]
    }.ret,
}
