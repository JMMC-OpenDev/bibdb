xquery version "3.1";

(:import module namespace app="http://apps.jmmc.fr/exist/apps/docmgr/templates" at "app.xql";:)
import module namespace app="http://olbin.org/exist/bibdb/templates" at "app.xql";
import module namespace config="http://olbin.org/exist/bibdb/config" at "config.xqm";

import module namespace adsabs="http://exist.jmmc.fr/jmmc-resources/adsabs" at "/db/apps/jmmc-resources/content/adsabs.xql";

declare function local:words-to-camel-case
  ( $arg as xs:string? )  as xs:string {
     string-join((tokenize($arg,'\s+')[1],
       for $word in tokenize($arg,'\s+')[position() > 1]
        return concat(upper-case(substring($word,1,1)), substring($word,2))
      ,''))
};


declare function local:do($node as node(), $model as map(*)?) {
let $log := util:log("info", "start ezviz output ")
let $prepare := app:retrieve-ads()
let $olbin := app:get-olbin()
let $records := $olbin//e
let $categories := $olbin//category
let $catnames := map:merge(for $c in $categories return map{$c/name: replace(local:words-to-camel-case($c/name),"HIDDEN","JMMC")})
let $nbrec := count($records)
let $node := $node
return ( for $r at $pos in $records
    let $bibcode := data($r/bibcode)
(:    let $log := util:log("info", "working on "||$bibcode):)
    let $log := if( $pos mod 100 = 0 ) then  util:log("info", "generating entry "||$pos|| "/"|| $nbrec) else ()
    let $ads-record := adsabs:get-records($bibcode)
    let $pubdate := adsabs:get-pub-date($ads-record)
    let $title := adsabs:get-title($ads-record)
    let $journal := adsabs:get-journal($ads-record)
    let $journal := app:normalize-journal-name($journal, $bibcode)
    return  
        <record>
            { 
(:                bibcode, pubdate, title, journal :)
(:                $r/*,:)
                element {"bibcode"} {$bibcode},
                element {"pubdate"} {$pubdate},
                element {"journal"}   {$journal},
                element {"title"}   {$title},
                $r/tag,
(:                for $c in $categories[tag=$r/tag]/name/text() return <category>{$c}</category>:)
                for $c in $categories 
                    let $ctags := $c/tag
                    return element {$catnames($c/name)}
                    {
                        let $tags := $r/tag[.=$ctags]
                        (: remove JMMC from JMMC category if not alone:)
                        let $tags := if($c/name="HIDDEN" and count($tags)>1) then $tags[not(.="JMMC")] else $tags
                        return 
                            string-join($tags, "/")
                    }
            }
        </record>,
        <json>
            {        
                for $c in $categories 
                    let $name := replace($c/name,"HIDDEN","JMMC")
                    let $id := local:words-to-camel-case($name)
                    let $e := <e>"${$id}": {{
        "label": "{$name}",
        "visible": false,
        "get":   "content.json.{$id}.#text",
        "default":"",
        "parseCSV" : "/",
        "foreach": {{
            "trim": true
        }},
        "remove":""
    }},
      </e>
            return $e/text()
            }  
    </json>,
    <json>
            {        
                for $c in $categories 
                    let $name := replace($c/name,"HIDDEN","JMMC")
                    let $id := local:words-to-camel-case($name)
                    let $e := <e>{{
        "field": "{$id}",
        "type": "pie",
        "title": "{$name}",
        "facets": [
            {{"label": "Journal", "path": "journal" }},
            {{"label": "Years", "path": "year" }},
            {
                let $lines := 
                    for $c2 in $categories let $name2 := replace($c2/name,"HIDDEN","JMMC") let $id2 := local:words-to-camel-case($name2)
                        return '            {"label": "'||$name2||'", "path": "'||$id2||'" }'                    
                return string-join($lines, ",&#10;")
            }
        ]
      }},
      </e>
            return $e/text()
            }        
    </json>)
};

<records>
    {local:do(<a/>,()), util:log("info", "finish ezviz output ")
}
</records>