xquery version "3.1";

import module namespace app="http://olbin.org/exist/bibdb/templates" at "modules/app.xql";

declare option exist:serialize "method=text media-type=text/csv";

let $olbin-doc := app:get-olbin()
let $categories := $olbin-doc//category
let $pubs := $olbin-doc//e
let $tags := for $t in app:get-olbin()//tag[@id] where $pubs//tag[.=$t] order by lower-case($t) return $t
return
    let $header := string-join(("YEAR", "total_pubs", for $cat in $categories return "&quot;"||data($cat/name)||"&quot;", for $tag in $tags return "&quot;"||data($tag)||"&quot;"), ",")
    let $data := for $p in $pubs group by $date:=substring($p/bibcode,1,4) order by $date descending        
        return string-join(
                    ($date,count($p),
                    for $cat in $categories return count($p//tag[.=$cat/tag]),
                    for $tag in $tags return count($p//tag[.=$tag])),
                    ","
                )
    return string-join( ($header, $data, ""), "&#10;")
