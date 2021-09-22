xquery version "3.1";

import module namespace app="http://olbin.org/exist/bibdb/templates" at "modules/app.xql";

declare option exist:serialize "method=text media-type=text/csv";

let $olbin-doc := app:get-olbin()
let $categories := $olbin-doc//category
let $all-pubs := $olbin-doc//e
let $pubs := $all-pubs
(:let $tags := for $t in $olbin-doc//tag[@id] where $pubs//tag[.=$t] order by lower-case($t) return $t:)
let $tags := for $t in $pubs//tag group by $t return $t[1]
(:  reduce number of papers to analyse according filter params :)
let $keep-tag := request:get-parameter("keep-tag", ())
let $ignore-tag := request:get-parameter("ignore-tag", ())
(: TODO ignore-tag :)
let $pubs := if(exists($keep-tag)) then $pubs[tag=$keep-tag] else $pubs
let $pubs := if(exists($ignore-tag)) then $pubs[not(tag=$ignore-tag)] else $pubs

let $header := string-join(("YEAR", "total_pubs", for $cat in $categories return "&quot;"||data($cat/name)||"&quot;", for $tag in $tags return "&quot;"||data($tag)||"&quot;"), ",")

let $all-by-year := map:merge( for $p in $all-pubs group by $date:=substring($p/bibcode,1,4) return map{ $date : $p } )
let $filtered-by-year := if(exists($keep-tag) or exists($ignore-tag)) then 
        map:merge( for $p in $pubs group by $date:=substring($p/bibcode,1,4) return map{ $date : $p } )
    else $all-by-year


let $data := for $year in map:keys( $all-by-year ) order by $year descending 
    let $p := map:get($filtered-by-year, $year)
    return string-join(
                ($year,count($p),
                for $cat in $categories return count($p//tag[.=$cat/tag]),
                for $tag in $tags return count($p//tag[.=$tag])),
                ","
            )
            
return
    string-join( ($header, $data, ""), "&#10;")
