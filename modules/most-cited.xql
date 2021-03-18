xquery version "3.1";

import module namespace adsabs="http://exist.jmmc.fr/jmmc-resources/adsabs" at "/db/apps/jmmc-resources/content/adsabs.xql";
declare namespace ads="http://ads.harvard.edu/schema/abs/1.1/abstracts"; 

let $analysis := doc("/ads/analysis.xml")/analysis (: store citations :)
let $records := collection("/ads")//ads:record
let $olbin := data($records/ads:bibcode)

(: prepare dataset if not present :)
let $datasets := for $o in $olbin return if($analysis/dataset[@bibcode=$o]) then () else update insert <dataset bibcode="{$o}"/> into $analysis


let $refs := ("2014A&amp;A...561A..46C", "2017ApJ...844...72W", "2017A&amp;A...602A..94G", "2020A&amp;A...642A.162G", "2020ApJ...897..180Z")
(:let $refs := ("2020A&amp;A...642A.162G", "2020ApJ...897..180Z"):)

let $world := for $r in $olbin 
    let $dataset := $analysis/dataset[@bibcode=$r]
(:    let $q:= "(references(identifier:"||$r||") OR citations(identifier:"||$r||")) property:refereed":)
(:    let $q:= "(references(identifier:"||$r||")) property:refereed":)
(:    let $q:= "(citations(identifier:"||$r||")) property:refereed":)
(:    let $search := adsabs:search($q, 'bibcode'):)
(:    let $bibcodes := parse-json($search)?response?docs?*?bibcode:)
(:    (: store if not present :):)
(:    let $store := for $b in $bibcodes order by $b return if($dataset//bibcode=$b) then () else update insert <bibcode>{$b}</bibcode> into $dataset:)
    return $dataset


let $fof := for $bi in data($world//bibcode) group by $b := $bi
    order by count($bi) descending
    where count($bi) >= 20 and not($b=$olbin)
(:    where count($bi) > 1:)
    return <bibcode count="{count($bi)}">{$b}</bibcode>
    
let $create-lib := adsabs:create-library("olbin-most-cited-candidates", "papers not in olbin-db but cited by more than 20 olbin papers", true(), data($fof))

let $fof := for $f at $pos in $fof return $pos || " #" || $f/@count||" : https://ui.adsabs.harvard.edu/abs/" || $f
(:    :)
return (count($fof), string-join ($fof,"&#10;"), count($olbin))
(:return $world:)