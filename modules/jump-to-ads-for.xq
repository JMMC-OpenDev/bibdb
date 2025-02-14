xquery version "3.1";

import module namespace adsabs="http://exist.jmmc.fr/jmmc-resources/adsabs" at "/db/apps/jmmc-resources/content/adsabs.xql";
declare namespace ads="https://ads.harvard.edu/schema/abs/1.1/abstracts";

let $tags := request:get-parameter("tag", ())
let $operator := request:get-parameter("operator", "")
let $operator := " " || $operator || " "
let $query := request:get-parameter("query", "")
(:let $query := "tokenize($query, " "):)
let $query := "(" || string-join(tokenize(tokenize($query, ","), " ")," or ") || ")"
(:   :let $query := "(" || string-join( tokenize($query,", \t\n") , " or " ) || "("  :)
let $query := if (string-length($query)>2) then "( " || adsabs:library-query("olbin-refereed")|| " and ( title:" || $query || " or year:" || $query || " or author:" || $query ||" or bibcode:" || $query || ") )" else ()

let $qlib := if(exists($tags[string-length(.)>1]))
    then
        for $tag in $tags[string-length(.)>1] return adsabs:library-query("tag-olbin "||$tag)
    else
        adsabs:library-query("olbin-refereed")

let $targets := request:get-parameter("target", ())
let $qtarget := if (exists($targets)) then
        let $t  := for $t in $targets return for $e in tokenize($t, ",") return "&quot;"|| normalize-space($e) ||"&quot;"
        return "object:(" || string-join($t," ") || ")"
    else
        ()
let $q := string-join(($qlib, $qtarget, $query), $operator)
return
    response:redirect-to(xs:anyURI($adsabs:SEARCH_ROOT||"q="||encode-for-uri($q)))
