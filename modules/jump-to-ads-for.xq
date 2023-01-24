xquery version "3.1";

import module namespace adsabs="http://exist.jmmc.fr/jmmc-resources/adsabs" at "/db/apps/jmmc-resources/content/adsabs.xql";
declare namespace ads="http://ads.harvard.edu/schema/abs/1.1/abstracts";

let $tags := request:get-parameter("tag", ())
let $qlib := if(exists($tags))
    then
        for $tag in $tags return adsabs:library-query("tag-olbin "||$tag)
    else
        adsabs:library-query("olbin-refereed")

let $targets := request:get-parameter("target", ())
let $qtarget := if (exists($targets)) then
        let $t  := for $t in $targets return for $e in tokenize($t, ",") return "&quot;"|| normalize-space($e) ||"&quot;"
        return "object:(" || string-join($t," ") || ")"
    else
        ()
let $q := string-join(($qlib, $qtarget), " ")
return
    response:redirect-to(xs:anyURI($adsabs:SEARCH_ROOT||"q="||encode-for-uri($q)))