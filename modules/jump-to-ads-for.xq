xquery version "3.1";

import module namespace adsabs="http://exist.jmmc.fr/jmmc-resources/adsabs" at "/db/apps/jmmc-resources/content/adsabs.xql";
declare namespace ads="http://ads.harvard.edu/schema/abs/1.1/abstracts"; 

let $tag := request:get-parameter("tag", ())
let $qlib := adsabs:library-query("tag-olbin "||$tag) (: don't forget to add prefix :)
return 
    response:redirect-to(xs:anyURI($adsabs:SEARCH_ROOT||"q="||encode-for-uri($qlib)))