 xquery version "3.1";

import module namespace adsabs="http://exist.jmmc.fr/jmmc-resources/adsabs" at "/db/apps/jmmc-resources/content/adsabs.xql";
declare namespace ads="https://ads.harvard.edu/schema/abs/1.1/abstracts"; 

(:most-cited.xql must be called before:)

let $analysis := doc("/ads/analysis.xml")/analysis (: store citations :)
let $records := collection("/ads")//ads:record
let $olbin := data($records/ads:bibcode)

(: limit to recent olbin pubs citations :)
let $olbin-citations := $analysis//dataset[substring(@bibcode,1,4)=(for $y in 2015 to 2020 return string($y))]
let $olbin-citations := for $b in $olbin-citations//bibcode group by $bibcode:=$b return $bibcode

(: prepare dataset if not present :)
let $friends := if ($analysis/friends) then () else ( update insert <friends/> into $analysis )
let $friends := $analysis/friends

(::)
let $datasets := if ($friends/friend) then () else 
    for $o in $olbin-citations let $friend := $friends/friend[@bibcode=$o] return if($friend) then () else (update insert <friend bibcode="{$o}"/> into $friends, util:log("info", "insert new friend "||$o) )

(:  search for every friend that has no bibcode yet :)
let $search-citations := if(true()) then () else for $friend in $friends/friend[not(bibcode)]
    let $bibcode := string($friend/@bibcode)
    let $q:= "(citations(identifier:"||$bibcode||")) property:refereed"
    let $log := util:log("info", $q)
    let $search := ()
    let $search := adsabs:search($q, 'bibcode')
    
    let $bibcodes := parse-json($search)?response?docs?*?bibcode

    (: store if not present :)
    let $store := for $b in $bibcodes order by $b return update insert <bibcode>{$b}</bibcode> into $friend
    return $bibcodes


let $fof := for $bi in $friends/friend/bibcode group by $b := $bi
    order by count($bi) descending
    where count($bi) >= 3  and not($b=$olbin)
    return <bibcode count="{count($bi)}">{$b}</bibcode>

let $most-cited := for $bi in $analysis/dataset/bibcode group by $b := $bi
    order by count($bi) descending
    where count($bi) >= 3  and not($b=$olbin)
    return <bibcode count="{count($bi)}">{$b}</bibcode>

    
(:let $create-lib := adsabs:create-library("olbin-friends-of-friends-candidates-3-10", "friends of friends on citations [3...10[ not in olbin-db", true(), data($fof)):)

(:let $fof := for $f at $pos in $fof return $pos || " #" || $f/@count||" : https://ui.adsabs.harvard.edu/abs/" || $f:)
(:return (count($fof), string-join ($fof,"&#10;"), count($friends)):)
(:(:return $world:):)
 return (
 for $b in ($fof,$most-cited) group by $bibcode := $b
    where count($b)>2
    return $bibcode
 ,count($fof)
 ,count($most-cited)
)