xquery version "3.1";

import module namespace adsabs="http://exist.jmmc.fr/jmmc-resources/adsabs" at "/db/apps/jmmc-resources/content/adsabs.xql";

declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";

declare function local:md-links($bibcodes){
    let $html-links := for $bibcode in $bibcodes return adsabs:get-link($bibcode, $bibcode)
  return string-join( for $link in $html-links return <l>[{string($link)}]({string($link/@href)})</l> , " " )
};


declare function local:first-affiliation($affs as array(*)) {
    
    let $ok := ("-","Australia","Belgium","Canada","Chile","China","Czech Republic","France","Germany","Ireland","Italy.;","Netherlands","PR China","People's Republic of China","People's Republic of China;","Portugal","Slovakia","Spain","Taiwan","UK","USA","the Netherlands")
    let $bad := ("1","2")
    
    let $aff := array:head($affs)
    
    (: keep the first value of co-affiliations - removing the one that have numeric or some subvalues , separated :)
    let $aff := (tokenize($aff, ";")[ not( matches( (tokenize(., ',')[normalize-space(.)])[last()] ,"[0-9]|Physics"))])[1] 
    
    (: extract last right non empty value :)
    let $aff := (tokenize($aff, ',')[normalize-space(.)])[last()] 
    
    (: remove wrong chars   :)
    let $aff := normalize-space(translate($aff,'.;',''))
    
    (: normalize China :)
    let $countries := ("China", "Netherlands")
    let $aff := if (matches($aff, string-join($countries,"|"),'i')) then $countries[matches($aff,.)]  else $aff
    return 
        $aff
};

let $tags := ( "MATISSE", "GRAVITY", "PIONIER", "AMBER")
let $queries := map:merge( for $tag in $tags return map:entry($tag,adsabs:library-query("tag-olbin "||$tag)) )


let $docs := map:for-each($queries, function($label, $query){
    let $doc0 := adsabs:search($query, "first_author_norm, aff,bibcode")?response?docs?*
    return
        for $doc1 in $doc0 group by $first_aff := local:first-affiliation($doc1?aff) , $first_author := $doc1?first_author_norm
        order by $first_aff, $first_author
        return 
            string-join( ( $label, count($doc1), $first_aff , $first_author, distinct-values(array:head($doc1[1]?aff)), string-join($doc1?bibcode,",") )!concat("&quot;",.,"&quot;") ,  ", " )
    })

let $md := if(false()) then () else 
    for $tag in $tags 
        let $label := $tag
        let $query := map:get($queries, $tag)
        return 
(:    map:for-each($queries, function($label, $query){:)
    let $doc0 := adsabs:search($query, "first_author_norm, aff, bibcode")?response?docs?*
    return
        ("# " || $label || " (" ||count($doc0) || ") [ADS]("|| adsabs:get-query-link($query, (),())/@href ||")"
        ,
        for $doc1 in $doc0 group by $first_aff := local:first-affiliation($doc1?aff)
        order by count($doc1) descending
        return (
            "## " ||count($doc1) || " : " || $first_aff
            ,for $doc2 in $doc1 group by $first_author := $doc2?first_author_norm
                order by count($doc2) descending
                return " * " || count($doc2) || " : " || $first_author || " (" || distinct-values(array:head($doc2[1]?aff)) || ") " || local:md-links($doc2?bibcode)
        ),""
        )
(:    }):)

let $h :=    response:set-header("Content-Type","text") 

(:return string-join( ($docs, $md), "&#10;" ):)
return string-join( ($md), "&#10;" )
