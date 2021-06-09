xquery version "3.1";

import module namespace app="http://olbin.org/exist/bibdb/templates" at "app.xql";
import module namespace adsabs="http://exist.jmmc.fr/jmmc-resources/adsabs" at "/db/apps/jmmc-resources/content/adsabs.xql";
declare namespace ads="http://ads.harvard.edu/schema/abs/1.1/abstracts"; 


(:  to avoid massive updates we can just compute list counts and update differences only  :)
declare function local:check-update($list-name, $bibcodes as xs:string*){
    let $ads-list := adsabs:get-libraries()?libraries?*[?name=$list-name]
    let $num_documents := number($ads-list?num_documents)
    let $count := number(count($bibcodes))
    let $log  := util:log("info", string-join(("check-updates for",$list-name, "got", $num_documents, "vs", $count)," " ))
    let $do-update := if( $count = $num_documents ) then false() else true()
    let $log  := util:log("info", string-join(("do it ?",$do-update)," " ))
    return 
        if ( count($bibcodes)=$num_documents ) 
        then ()
(:        $list-name || " uptodate" :)
        else 
            let $id := $ads-list?id
            let $ads-bibcodes:= data(adsabs:search("docs(library/"||$id||")", "bibcode")?response?docs?*?bibcode)
            let $missings := $bibcodes[not(.=$ads-bibcodes)]
            let $outdated := $ads-bibcodes[not(.=$bibcodes)]
            let $update-a := if(true() and exists($missings)) then adsabs:library-add($id, $missings) else ()
            let $update-r := if($outdated) then adsabs:library-remove($id, $outdated) else ()
            (: todo after insert in olbin-refereed : remove all new ones from olbin-missings :)
            return 
            ($update-a, $update-r,$list-name || " need sync (olbin db:" || count($bibcodes) || ", ads:" ||  $num_documents|| ") : missing are "|| string-join($missings, " OR ") || ", outdated are "|| string-join($outdated, " OR ") )
};

let $clear-olbin := cache:remove($app:expirable-cache-name, "olbin-xml")
let $clear-ads := cache:clear($adsabs:expirable-cache-name)
let $entries :=  app:get-olbin()//e
let $bibcodes := $entries//bibcode
let $existing-lib-names := data(adsabs:get-libraries(false())?libraries?*?name)

let $res := () (: stack results :)

(: Perform lazy creation :)

let $res := ($res, 
    for $tag in app:get-olbin()//publications/tag[ not( . = ("Narrabri Stellar Intensity Interferometer") ) ]
    let $bibcodes := $entries[tag=$tag]/bibcode
    let $name := "tag-olbin "||$tag
    where not($name=$existing-lib-names)
    let $create-lib := try {
        let $update := adsabs:create-library($name, "Olbin papers tagged "||$tag, true(), data($bibcodes))    
(:        let $a := 1:)
  (: tag is probably too long :)
        return ()
    } catch * {
        $tag 
    }
  return data($name)||":"||count($bibcodes) || " ret"||$create-lib
(:    , adsabs:create-library("olbin-missing-pubs", "Missing Olbin papers to be added in the main db", true(), () ):)
)

let $res := ($res, 
    if($existing-lib-names='olbin-blacklist') then () else
    let $bbs := $app:blacklist-doc//bibcode
    (:return count($bbs):)
    return adsabs:create-library("olbin-blacklist", "Candidates (auto generated) papers sorted out from main Olbin list (reasons should be provided on bibdbmgr website). Helps to curate main lists.", true(), $bbs )
)
let $telbibcodes := doc($app:telbib-vlti-url)//bibcode

let $res := ($res, if($existing-lib-names='telbib-vlti') then () else adsabs:create-library("telbib-vlti", "Extract from telbib.", true(), () ) )

(:  now that every list is present, do update them  :)
let $res := ($res , local:check-update("telbib-vlti", $telbibcodes))
 

let $res := ($res , local:check-update("olbin-refereed", $bibcodes))

let $res := ( $res, for $tag in app:get-olbin()/publications/tag
        let $bibcodes := $entries[tag=$tag]/bibcode
        let $list-name := "tag-olbin "||$tag
        where $list-name = $existing-lib-names
        return local:check-update($list-name, $bibcodes)
    )
    
let $clear-libraries := cache:remove($adsabs:expirable-cache-name, "/biblib/libraries")
let $ask-again := adsabs:get-libraries()

return $res

(:return adsabs:get-libraries()?libraries?*[?name='olbin-refereed']:)
(:for $list in $existing-lib-names:)
(:    return $list:)
(:return  count($entries//e) = $num_documents:)
