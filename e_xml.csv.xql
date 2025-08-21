xquery version "3.1";

import module namespace app="http://olbin.org/exist/bibdb/templates" at "modules/app.xql";

(:declare option exist:serialize "method=text media-type=text/csv";:)
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "text";
declare option output:media-type "text/csv";

(: Prepare a csv for each bibcode adding one column per category filled by matching tags :)

let $pubs := app:get-olbin()//e
let $tags := app:get-olbin()//tag[@id]
let $categories := app:get-olbin()//category
let $headers := ("BIBCODE", for $cat in $categories return $cat/name)
return
    let $header := translate( upper-case( string-join($headers , ",") ), " ", "_")
    let $data := for $p in $pubs 
        return string-join(
                    (
                        $p/bibcode,
                        for $cat in $categories 
                            let $ctags := $cat/tag[.=$p/tag]
                            return "&quot;"||string-join($ctags,",")||"&quot;"
                    )
                    ,","
                )
    return string-join( ($header, $data, ""), "&#10;")
 
