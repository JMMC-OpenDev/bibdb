xquery version "3.1";

import module namespace app="http://olbin.org/exist/bibdb/templates" at "app.xql";

declare option exist:serialize "method=text media-type=text/plain";


"categories={&#10;" || 
string-join(
    (
        for $category  in app:get-olbin()//categories/category
        let $tags := for $tag in $category/tag return "'"||$tag||"'"
        let $tags := "[" || string-join( $tags, ", ") ||"]"
        return 
            "&apos;" || $category/name ||"&apos;:" || $tags
    )
    ,",&#10;"
    ) 
|| "&#10;}"