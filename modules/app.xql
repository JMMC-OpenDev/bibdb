xquery version "3.1";

module namespace app="http://olbin.org/exist/bibdb/templates";

import module namespace templates="http://exist-db.org/xquery/html-templating";
import module namespace lib="http://exist-db.org/xquery/html-templating/lib";
import module namespace config="http://olbin.org/exist/bibdb/config" at "config.xqm";
import module namespace adsabs="http://exist.jmmc.fr/jmmc-resources/adsabs" at "/db/apps/jmmc-resources/content/adsabs.xql";
import module namespace jmmc-auth="http://exist.jmmc.fr/jmmc-resources/auth";

import module namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace rest="http://exquery.org/ns/restxq";
(:declare variable $app:olbin-doc := doc($config:data-root||"/olbin.xml"); replace by app:get-olbin:)
declare variable $app:jmmc-doc := doc($config:data-root||"/jmmc.xml");
declare variable $app:curation-doc := doc($config:data-root||"/curation.xml")/*;
declare variable $app:blacklist-doc := doc($config:data-root||"/blacklists.xml");
(:declare variable $app:journal-names-doc := doc($config:data-root||"/journal-names.xml");:)
 declare variable $app:journal-names-doc := doc("/db/apps/bibdb-data/data/journal-names.xml");
(: declare variable $app:ads-journals := doc($config:data-root||"/ads-journals.xml")//journal;:)
 declare variable $app:ads-journals := doc("/db/apps/bibdb-data/data/ads-journals.xml")//journal;


declare variable $app:LIST-JMMC-PAPERS  := "jmmc-papers";
declare variable $app:LIST-NON-INTERFERO  := "jmmc-non-interfero";
declare variable $app:LIST-OLBIN-REFEREED := "olbin-refereed";
declare variable $app:LIST-OLBIN-BLACKLIST := "olbin-blacklist";

declare variable $app:ADS-COLOR := "primary";
declare variable $app:OLBIN-COLOR := "success";

declare variable $app:expirable-cache-name :="bibdbmgrcache";
declare variable $app:expirable-cache := cache:create($app:expirable-cache-name,map { "expireAfterAccess": 600000 }); (: 10min :)

declare variable $app:telbib-vlti-url := "http://telbib.eso.org/api.php?telescope[]=vlti+visitor&amp;telescope[]=vlti";

declare function app:get-olbin(){
    let $xml := cache:get($app:expirable-cache-name, "olbin-xml")
    return 
        if($xml) 
        then
            $xml 
        else
            let $doc := doc("http://apps.jmmc.fr/bibdb/xml")
(:            let $store := xmldb:store($config:data-root, "olbin.xml", $doc) :)
            let $store := cache:put($app:expirable-cache-name, "olbin-xml", $doc)
            let $log  := util:log("info", "olbin-xml updated")
            return $doc
};

declare function app:retrieve-ads() {
    let $bibcodes := app:get-olbin()//bibcode
    let $records := adsabs:get-records($bibcodes, true())
    return ()
};

declare function app:init-data($node as node(), $model as map(*)) {
(:    let $log := util:log("info", "logged as "|| serialize(sm:id())):)
    let $xml := app:get-olbin()
    let $bibcodes := $xml//bibcode
    (: Why ?   let $retrieve-ads := app:retrieve-ads():)
    let $ads-libraries := adsabs:get-libraries()
    let $last-ads-mod-date := max($ads-libraries?*?*?date_last_modified)
    let $ads-nb-pubs := data(adsabs:get-libraries()?libraries?*[?name=$app:LIST-OLBIN-REFEREED]?num_documents)
    
    (: If count of both list differs we could then synchronize olbin onto ADS and for the new associated tag ones 
    look at jmmc-references()
    :)
    return 
        map {
            'olbin-nb-pubs': count($bibcodes)
            ,'ads-nb-pubs': $ads-nb-pubs
            ,'date-last-olbin-update': substring(((for $d in $xml//subdate order by $d descending return $d)[1]),1,16)
            ,'date-last-ads-update': substring($last-ads-mod-date,1,16)

        }
};



(:~
 : Search in db if we have the associated journal value and return single name or use given string.
 : we have to search with all journal codes matching start of bibstem but keep the first only.
 : TODO improce speedup since bibcode may only be checked accross JJJJ chars 
 :   see : https://ui.adsabs.harvard.edu/help/actions/bibcode
 : 
 : @param $journal journal value as returned by ADS 
 :)
declare function app:normalize-journal-name($name as xs:string?, $bibcode as xs:string)as xs:string{
    let $ojkey := "ordered-journals"
    let $cjkey := "cached-journals"
    let $journals := cache:get($app:expirable-cache-name, $ojkey)
    let $journals := if(exists($journals)) 
        then
            $journals
        else
            let $j := for $j in $app:ads-journals order by string-length($j/code) descending return $j
            let $cache := cache:put($app:expirable-cache-name, $ojkey, $j)
            return $j
    
    let $bibstem := substring($bibcode, 5)
    
    let $cached-journals := cache:get($app:expirable-cache-name, $cjkey)
    
    let $matched-journals := for $j in $cached-journals[code[starts-with($bibstem, .)]] order by string-length($j/code) descending return $j
    
    let  $matched-journals := if(exists($matched-journals)) 
        then 
            (
(:            util:log("info", "Found in cache : size="||count($cached-journals)),:)
(:            if(count($matched-journals)>1) then util:log("info", "Found multiples journals for '"|| $bibstem ||"' : "||string-join(for $m in $matched-journals return $m/name, "; ")) else (),:)
            $matched-journals[1]
            )
        else 
            let $search-in-all := for $j in $journals[code[starts-with($bibstem, .)]] order by string-length($j/code) descending return $j
            
            let $add-in-cache := if(exists($search-in-all)) then cache:put($app:expirable-cache-name, $cjkey, ($cached-journals,$search-in-all) ) else ()
            return $search-in-all[1]
    
    let $jname := ($matched-journals/name)
(:    let $log := util:log("info", "bibstem: "||$bibstem || " -> " || $jname ):)
    return 
        if( exists($jname) ) then $jname else 
            ( util:log("info", "Nothing dound using given name : "|| $name ), $name )
};


(:~
 : Search in db if we have the associated journal value and return single name or use given string.
 : 
 : @param $journal journal value as returned by ADS 
 :)
declare function app:normalize-journal-name-old($name as xs:string?, $bibcode as xs:string)as xs:string?{
    let $name := normalize-space($name)
    return
        if(string-length($name)<2) then (util:log("info","missing journal name"), $name)
        else 
            let $bbistem := substring($bibcode, 4,6)
            let $journals := $app:journal-names-doc//journal
(:            let $journal := $journals[name[matches(translate($name,"&amp;",""),translate(.,"&amp;",""))]] [1]:)
            let $journal := $journals[matches(translate($name,"&amp;",""),translate(name,"&amp;",""))] [1]
            let $journal := if(exists($journal)) then $journal else $journals[value[starts-with($name,.)]][1]
            
            return if(exists($journal)) then (
(:                util:log("info","found journal '"|| $journal/name || "' for : '" || $name||"'"), :)
                    $journal/name
                ) else 
                (
                    util:log("info","You may add a new journal entry for :'" || $name|| "'" || $journals[starts-with(translate($name,"&amp;",""),translate(name,"&amp;",""))] ),
                    $name
                )
};


declare function app:show-ads-lists($prefix as xs:string*) {
    let $public-libs := adsabs:get-libraries()?libraries?*[?public=true()]

    for $lib in $public-libs
        let $id := $lib?id
        let $name := $lib?name
        where tokenize($name,"-")=$prefix
        let $date_last_modified := $lib?date_last_modified
        (:"public": true(), "num_users": 3.0e0,   "permission": "owner",    "owner": "jmmc-tech-group",  "date_created": "2020-10-13T15:41:04.952404" :)
        let $description:= $lib?description
        let $num_documents:= $lib?num_documents
        let $perms := adsabs:library-get-permissions($id)
        let $title := "last mod date "||$date_last_modified 
        return <p><a href="https://ui.adsabs.harvard.edu/search/q=docs(library%2F{$id})" title="library/{$id} : {$title}" alt="ads list">{$name}</a>&#160;<span class="badge" title="on ADS">{$num_documents}</span>&#160;<img class="clippy" data-clipboard-text="docs(library/{$id})" src="resources/images/clippy.svg" alt="Copy to clipboard" width="13"/> : {$description} <br/> 
        {
         for $m in $perms?* return <ul>{for $key in map:keys($m) where not(starts-with($key,"jmmc-tech-group@")) return <li>{jmmc-auth:get-obfuscated-email($key)||"("|| map:get($m,$key) ||")"}</li>}</ul>
        }
        </p>
};

declare function app:filtered-journals($node as node(), $model as map(*)) {
    for $j in $adsabs:filtered-journals return <li>{$j}</li>
};


declare function app:olbin-ads-lists($node as node(), $model as map(*)) {
    app:show-ads-lists("olbin")
};


declare function app:olbin-tag-lists($node as node(), $model as map(*)) {
    let $json-ads-lists := adsabs:get-libraries()?libraries?*[?public=true() and ?name[starts-with(., "tag-olbin")] ]
    return
    <ul class="list-group">{for $cat in app:get-olbin()//category[tag]
        return
            <li class="list-group-item"><span class="label label-success">{data($cat/name)}</span>:<em>{data($cat/description)}</em><ul class="list-inline">
            {
                for $tag in data($cat/tag) 
                    let $name := 'tag-olbin '||$tag
                    let $li := $json-ads-lists[?name=$name]
                    let $id := $li?id 
                    let $title:= serialize(<div>Name: {$li?name}<br/>Num documents: {$li?num_documents}<br/>Date last modified: {$li?date_last_modified}<br/>id: {$id}</div>)
                    order by $name
                    return <li><a href="https://ui.adsabs.harvard.edu/search/q=docs(library%2F{$id})" rel="tooltip" data-html="true" data-original-title="{$title}" alt="ads link">{$tag}</a> &#160;<img class="clippy" data-clipboard-text="docs(library/{$id})" src="resources/images/clippy.svg" alt="Copy to clipboard" width="13"/></li>
            }</ul></li>
    }</ul>
};


declare function app:olbin-ads-sample-citation-link($node as node(), $model as map(*)) {
    let $id := adsabs:get-libraries()?libraries?*[?public=true() and ?name[.="olbin-refereed"] ]?id
    let $l := "docs(library/"||$id||")"
    let $queries := [()
        ,[("Which impact of OLBIN outside its own field ?" , "property:refereed references("||$l||") - "||$l)]
        ,[("Are these bibcodes in OLBIN ?" , '(2020Natur.584..547G OR 1984vlti.conf..603L) '||$l)]
        ,[("Are these bibcodes in OLBIN (safer query)?" , 'bibcode:("2020Natur.584..547G" OR "1984vlti.conf..603L") '||$l)]
        ,[("Which one is not in OLBIN ?" , 'bibcode:("2020Natur.584..547G" OR "1976Rech....7..910B") - '||$l)]
        ,[("My (refereed) papers part of (refereed) OLBIN ?" , 'author:"Benisty, M" + '||$l)]
        ,[("My refereed papers not part of refereed OLBIN ?" , 'property:refereed author:"Benisty, M" - '||$l)]
        ,[("Is this keyword in the full text papers of OLBIN ?" , 'full:"AMHRA" + '||$l)]
    ]
    
    return 
        <ul class="list-group">
            { 
                for $samplea in $queries?*
                let $sample := $samplea?*
                let $url := "https://ui.adsabs.harvard.edu/search/q="||encode-for-uri($sample[2])
                return <li class="list-group-item"><a href="{$url}">{$sample[1]}</a>:<br/> <code>{$sample[2]}</code></li>
            }
        </ul>
};


declare function app:summary($node as node(), $model as map(*)) {
    <p>Welcome on the OLBIN  publications management area. <a href="http://www.jmmc.fr/bibdb">Visit the current portal.</a>
    <br/> This web area is a <b>*work in progress*</b>. 
    <br/>Main goals are: 
    <ul>
        <li>Improve tools to meter publications related to OLBIN and it's sublists taking advantage of tagging provided by the content tracker (Alain Chelli).</li>
        <li>Keep OLBIN paper list up to date taking advantage of the nice <a href="https://ui.adsabs.harvard.edu">NASA/ADS</a> API.</li>
    </ul>
    <br/>{map:get($model,"olbin-nb-pubs")} OLBIN publications (last update on {map:get($model,"date-last-olbin-update")} , last ads list synchronization on {map:get($model,"date-last-ads-update")}).
    <br/>Please contact the <a href="http://www.jmmc.fr/support">jmmc user support</a> for any remark, question or idea. Directions to enter the collaborative mode should come ...
    </p>
};



declare function app:others-lists($node as node(), $model as map(*)) {
    let $jmdc-csv-libname := 'jmdc-csv'
    let $jmdc-csv-interfero-libname := 'jmdc-csv-interfero'
    
    let $jmdc-csv := cache:get($app:expirable-cache-name,$jmdc-csv-libname)
    let $jmdc-csv := if ($jmdc-csv) then $jmdc-csv else (
        cache:put($app:expirable-cache-name,$jmdc-csv-libname,tail(hc:send-request( <hc:request href="http://jmdc.jmmc.fr/export_csv" method="GET"/> ))),
        cache:get($app:expirable-cache-name,$jmdc-csv-libname)
        )
        
    let $headers := tokenize(substring-before($jmdc-csv, "&#10;")[1], ",") ! translate(. , '"', '')
    let $csv-lines := tokenize($jmdc-csv, "&#10;")[position()>1]
        
    let $jmdc-bibcodes:= distinct-values( for $line in $csv-lines return translate(tokenize($line, ",")[last()-1], '"', '') )
    let $jmdc-bibcodes:= $jmdc-bibcodes[not(contains(., "............"))]
    
    let $jmdc-interfero-bibcodes:= distinct-values( 
            for $line in $csv-lines
            let $els := tokenize($line, ",")
            let $method := $els[index-of($headers, "METHOD")]
            where contains($method, ("1","3"))
                let $bib := translate($els[last()-1], '"', '') 
                return $bib
            )[not(contains(., "............"))]
    
    let $fresh-libraries := adsabs:get-libraries(false())
    let $existing-lib-names := data($fresh-libraries?libraries?*?name)
    let $create-if-missing := if($existing-lib-names=$jmdc-csv-libname) then () else adsabs:create-library($jmdc-csv-libname, "Extract from jmdc.jmmc.fr.", true(), () ) 
    let $create-if-missing := if($existing-lib-names=$jmdc-csv-interfero-libname) then () else adsabs:create-library($jmdc-csv-interfero-libname, "Extract from jmdc.jmmc.fr / only method 1 and 3.", true(), () ) 
    let $check-update := app:check-update($fresh-libraries, $jmdc-csv-libname, $jmdc-bibcodes, true())
    let $check-update := app:check-update($fresh-libraries, $jmdc-csv-interfero-libname, $jmdc-interfero-bibcodes, true())
    
    let $q1 := adsabs:library-query($jmdc-csv-libname)
    let $q2 := adsabs:library-query($app:LIST-OLBIN-REFEREED) || " " || $q1
    let $q3 := " - " || $q2

    let $q11 := adsabs:library-query($jmdc-csv-interfero-libname)
    let $q12 := adsabs:library-query($app:LIST-OLBIN-REFEREED) || " " || $q11
    let $q13 := " - " || $q12
    let $q14 := adsabs:library-query("tag-olbin Stellar diameters") || " " || $q11
    let $q15 := " - " || $q14

    
    return 
    <div>
        <h1>JMDC</h1>
        <p> extracted from jmdc.jmmc.fr:
        <ul>
                <li>{adsabs:get-query-link($q1,"All JMDC reference papers")} : {count($jmdc-bibcodes)} bibcodes 
                    <ul><li> {adsabs:get-query-link($q2," part of Olbin")}</li><li> {adsabs:get-query-link($q3," not part of Olbin")}</li></ul>
                </li>
                <li>{adsabs:get-query-link($q11,"JMDC reference papers from optical interferometry or intensity interferometry methods")} : {count($jmdc-interfero-bibcodes)} bibcodes 
                    <ul><li> {adsabs:get-query-link($q12," part of Olbin")}</li><li> {adsabs:get-query-link($q13," not part of Olbin")}</li></ul>
                    <ul><li> {adsabs:get-query-link($q14," part of Olbin.Stellar diameters")}</li><li> {adsabs:get-query-link($q15," not part of Olbin.Stellar diameters")}</li></ul>
                </li>
            </ul>
            <em>Note: bibcodes with ............ are filtered out</em>
        </p>
    </div>
};


declare function app:jmmc-summary($node as node(), $model as map(*)) {
    <p>Welcome on the JMMC publications management area.<br/>
        {app:badge("OLBIN", map:get($model,"olbin-nb-pubs"), $app:OLBIN-COLOR)} last update : <em>{map:get($model,"date-last-olbin-update")}</em>,
        {app:badge("ADS", map:get($model,"ads-nb-pubs"), $app:ADS-COLOR)} last update : <em>{map:get($model,"date-last-ads-update")}</em>
    </p>
};

declare function app:jmmc-ads-lists($node as node(), $model as map(*)) {
    app:show-ads-lists("jmmc"),
    app:show-ads-lists("oidb"),
    app:show-ads-lists("telbib")
};

(: Default Primary Success Info Warning Danger:)
declare function app:badge($left, $right, $style){
    <span class="label-badge">&#160;<span class="label label-default label-badge-left">{$left}</span><span class="label label-{lower-case($style)} label-badge-right ">{$right}</span>&#160;</span>
};

declare function app:check-updates($node as node(), $model as map(*)) {

    if(cache:keys($adsabs:expirable-cache-name)="/biblib/libraries") then 
        let $old := adsabs:get-libraries() 
        let $refresh:= session:get-creation-time()
        let $new := adsabs:get-libraries(false()) (: force refresh :) 
(:            let $new := adsabs:get-libraries(true()):)
        return if( max($new?*?*?date_last_modified) > max($old?*?*?date_last_modified) ) then 
            ( util:log("info", "update required"), cache:clear($adsabs:expirable-cache-name) (: clear caches... :)
            ,<div class="alert alert-warning fade in">
                    <button type="button" class="close" data-dismiss="alert" aria-hidden="true">×</button>
                    <strong>Sorry for the additional delay!</strong> The lists just have been synchronized with ADS.
                </div>
            )
            else
                util:log("info", "we seems uptodate")
        else () (: nothing to do : next call will come later, this avoid 2 calls instead of 1 :)
};

declare function app:jmmc-references($node as node(), $model as map(*)) {
    let $jmmc-groups := $app:jmmc-doc//group[@tag]
    let $jmmc-groups-bibcodes := data($jmmc-groups/bibcode)
    
    let $olbin-doc := app:get-olbin()
    let $olbin-bibcodes := data($olbin-doc//bibcode) (: could be ads list ? :)
    let $non-interfero-bibcodes := data(adsabs:library-get-bibcodes($app:LIST-NON-INTERFERO))
    let $blacklist-bibcodes := data(adsabs:library-get-bibcodes($app:LIST-OLBIN-BLACKLIST))
    let $jmmc-papers-bibcodes := data(adsabs:library-get-bibcodes($app:LIST-JMMC-PAPERS))
    
    let $olbin-refereed-q := adsabs:library-get-search-expr($app:LIST-OLBIN-REFEREED)
    let $non-interfero-q := adsabs:library-get-search-expr($app:LIST-NON-INTERFERO)
    let $blacklist-q := "( " || adsabs:library-get-search-expr($app:LIST-OLBIN-BLACKLIST) || " OR bibstem:(" || string-join($adsabs:filtered-journals, " OR ") || ") )"

    
    (: Higlight jmmc-papers and blacklist present on ADS and missing in the xml db :)
(:    let $missing-in-blacklist := for $record in adsabs:get-records($jmmc-papers-bibcodes[not(.=$jmmc-groups-bibcodes)]) return <li>&lt;!--{adsabs:get-title($record)}--&gt;<br/>{ serialize(<bibcode>{adsabs:get-bibcode($record)}</bibcode>)} </li>:)
(:    let $missing-in-groups := if($missing-in-groups) then <div><h4>ADS jmmc-papers not present in local db</h4><ul> {$missing-in-groups}</ul></div> else ():)
    
    let $missing-jmmc-papers-bibcodes := $jmmc-groups-bibcodes[not(.=$jmmc-papers-bibcodes)]
    let $missing-jmmc-papers := if(exists($missing-jmmc-papers-bibcodes)) then "identifier:("|| string-join($missing-jmmc-papers-bibcodes, ' or ')||")" else ()
    let $missing-jmmc-papers := if($missing-jmmc-papers) then adsabs:get-query-link($missing-jmmc-papers,"Please add next jmmc-papers in ADS or move out xmldb") else ()
(:        <div><h4>ADS jmmc-papers contains all xmldb papers</h4></div>:)
    
    
    let $missing-in-groups := for $record in adsabs:get-records($jmmc-papers-bibcodes[not(.=$jmmc-groups-bibcodes)]) return <li>&lt;!--{adsabs:get-title($record)}--&gt;<br/>{ serialize(<bibcode>{adsabs:get-bibcode($record)}</bibcode>)} </li>
    let $missing-in-groups := if($missing-in-groups) then <div><h4>ADS jmmc-papers not present in local db</h4><ul> {$missing-in-groups}</ul></div> else ()
(:        <div><h4>ADS jmmc-papers present in local db</h4></div>:)
    
    
    (: The the big query behind:)
    
    let $base-query := "( " || string-join( ($app:jmmc-doc/jmmc/query) , " or " ) || " ) "
    let $big-q := "( " || $base-query || " and full:( " ||string-join( $jmmc-groups/@tag[not(.='tbd')] , " or ") || ") ) or ( citations(identifier:(" || string-join( $jmmc-groups-bibcodes , " or ") || ")) )"
    let $big-query := adsabs:get-query-link($big-q,<b data-trigger="hover" data-toggle="popover" data-original-title="This query" data-content="is a naïve one on top of the citations of jmmc papers and some full text query on top of associated kaywords">Global search</b>)
    let $big-q := $big-q || " - " || $olbin-refereed-q
(:    let $big-query := ( $big-query, " ", adsabs:get-query-link($big-q,<span data-trigger="hover" data-toggle="popover" data-original-title="This query" data-content="exclude OLBIN LIST of the preivous one"> - olbin-refereed</span>) ):)
    let $big-q := $big-q || " - " || $non-interfero-q
(:    let $big-query := ( $big-query, " ", adsabs:get-query-link($big-q,<span data-trigger="hover" data-toggle="popover" data-original-title="This query" data-content="exclude JMMC complimentary LIST of the preivous one"> - jmmc-non-interfero</span>) ):)
    let $big-q := $big-q || " - " || $blacklist-q
    let $big-query := ( $big-query, " =&gt; ",adsabs:get-query-link($big-q,<span><b data-trigger="hover" data-toggle="popover" data-original-title="How to fix ?" data-content="1st add the missing OLBIN in its db 2nd login to ADS and select the ones to be added in jmmc-non-interfero or olbin-blacklist lists"> check any missing candidates</b></span>))
    let $big-query := <p>{( <span>{$big-query}</span>)}</p>
    
    
    let $legend := <p><i class="text-success glyphicon glyphicon-ok-circle"/> present in OLBIN, <i class="text-warning glyphicon glyphicon-plus-sign"/> missing , <i class="glyphicon glyphicon-ban-circle"/> non refereed (or SPIE, ASCS), <i class="glyphicon glyphicon-bookmark"/> non-interfero, <s>blacklisted</s>  </p>
    
    let $groups := 
        for $group in $jmmc-groups
            let $tag := data($group/@tag)
            let $records := adsabs:get-records($group/bibcode)
            let $q := string-join($group/bibcode , " or ")
            let $q := if($q) then "( citations(identifier:("||$q||")) )" else ()
            let $citations-link := if($q) then adsabs:get-query-link($q,"view all citations on ADS") else ()
            let $q := string-join((data($q), "( " || $base-query || ' and full:"' || lower-case($group/@tag) ||'" )' )," or ")
            let $citations-link := ($citations-link, adsabs:get-query-link($q," + keywords "))
            let $q := $q || " - " || $olbin-refereed-q
(:            let $citations-link := ($citations-link, adsabs:get-query-link($q," - OLBIN ")):)
            let $q := $q || " property:refereed"
(:            let $citations-link := ($citations-link, adsabs:get-query-link($q," - non-refereed ")):)
            let $q := $q || " - " || $blacklist-q
            let $citations-link := ($citations-link, " =&gt; ", adsabs:get-query-link($q,"check any missing candidates"))
            
            
            let $ads-lib-count := data(adsabs:get-libraries()?libraries?*[?name="tag-olbin "||$tag ]?num_documents)
            let $badges :=  (app:badge("OLBIN",count($olbin-doc//e/tag[.=$tag]),$app:OLBIN-COLOR),if ($ads-lib-count) then app:badge("ADS",$ads-lib-count,$app:ADS-COLOR) else ())
                
            let $ol := for $record in $records
                let $bibcode := adsabs:get-bibcode($record)
                let $year := adsabs:get-pub-date($record)
                order by $year descending
(:                let $citations := adsabs:get-refereed-citations($bibcode):)
(:                let $missing-citations := :)
(:                    for $c in $citations order by $c where not($c=($olbin-bibcodes, $non-interfero-bibcodes)) :)
(:                        let $links := ( <a href="http://jmmc.fr/bibdb/addPub?bibcode={encode-for-uri($c)}"><i class="text-warning glyphicon glyphicon-plus-sign"/>&#160;</a> , adsabs:get-link($c,())):)
(:                        return <li>{if(app:is-blacklisted($c)) then <s>{$links}</s> else $links}</li>:)
(:                let $non-interfero-citations := :)
(:                    for $c in $citations order by $c where $c=$non-interfero-bibcodes:)
(:                        return <li><i class="glyphicon glyphicon-bookmark"/>{adsabs:get-link($c,())}</li>                        :)
                let $check-sign := if (adsabs:is-refereed($record)) then if ($olbin-bibcodes=$bibcode) then <i class="text-success glyphicon glyphicon-ok-circle"/> else <i class="text-warning glyphicon glyphicon-plus-sign"/> else <i class="glyphicon glyphicon-ban-circle"/>
                return
                    <li>
                        {$check-sign}&#160;{adsabs:get-html($record, 3)}<br/>
                    </li>
                    
(:<ul class="list-inline">:)
(:                        <li><span class="badge">{count($citations)}</span> refereed citations {if (exists($missing-citations)) then (<span> / missing in olbin or non interferometric papers: </span>,$missing-citations) else ()}</li>:)
(:                        </ul>:)
(:                        <ul class="list-inline">{$non-interfero-citations}</ul>                    :)
    
            let $title := $group/description
(:        return <li class="list-group-item" ><b>{$tag}</b>({$citations-link})<ol>{$ol}</ol></li>:)
        return <div id="collapse-{$tag}" class="panel-collapse collapse in ">
                <div class="panel-body"><b data-toggle="popover" data-trigger="hover" data-original-title="{$title}" data-content="">{$tag}</b> {$badges} ({$citations-link})<ol>{$ol}</ol></div></div>
    
    let $groups := <div class="panel-group" id="accordion">
        <div class="panel panel-default">
        <div class="panel-heading">
          <h4 class="panel-title">
            {()
(:                for $group in $jmmc-groups    :)
(:                return <a data-toggle="collapse" data-parent="#accordion" href="#collapse-{$group/@tag}">&#160;{data($group/@tag)}&#160;</a>:)
            }
          </h4>
        </div>
        {$groups[name()="div"]}
        </div>
        </div>
        
        
    return ($missing-jmmc-papers, $missing-in-groups, $big-query, $legend, <ul class="list-group">{$groups}</ul>)
};

declare function app:get-interferometers(){
    
(:    map:merge(for $e in sort(data(app:get-olbin()//categories/category[name="Facility"]/tag)) return map{$e:$e} ) :)
    let $interferometers := 
    map {
    "CHARA": "CHARA",
    "COAST": "COAST",
    "GI2T": "GI2T",
    "HYPERTELESCOPES": ("HYPERTELESCOPES","Hypertelescope"),
    "I2T": "I2T",
    "IACT": "Imaging Atmospheric Cherenkov Telescopes",
    "IOTA": "IOTA",
    "IRMA": "IRMA",
   "ISI ": "ISI ",
    "Keck": "Keck  Interferometer",
    "LBTI": "LBTI",
    "Mark III": "Mark III",
    "Narrabri Stellar Intensity Interferometer": ("Narrabri Stellar Intensity Interferometer", "Narrabri Intensity"),
    "NPOI": "NPOI",
    "PTI": "PTI",
(:    "SIM": "SIM",:)
    "SUSI": "SUSI",
    "Tcherenkov telescopes": "Tcherenkov telescopes",
    "VLTI": "VLTI"
    }


    return $interferometers
};

declare function app:jmmc-non-interfero($node as node(), $model as map(*)){
   <div>
        <h2>Helpers to catch OLBIN papers ( pour Alain! )</h2>
        <ol>{
        let $olbin-refereed-q := adsabs:library-get-search-expr($app:LIST-OLBIN-REFEREED)
        let $non-interfero-q := adsabs:library-get-search-expr($app:LIST-NON-INTERFERO)
        let $blacklist-q := "( " || adsabs:library-get-search-expr($app:LIST-OLBIN-BLACKLIST) || " OR bibstem:(" || string-join($adsabs:filtered-journals, " OR ") || ") )"
        
        let $interferometers :=  ( map:for-each(app:get-interferometers(), function($k,$v) { $v}) ! concat('"',.,'"') => string-join(" or ") ) ! concat('(',.,')')
        
        (: The the big query behind:)
        let $big-q := "property:refereed abs:"||$interferometers
        let $big-query := adsabs:get-query-link($big-q,<b data-trigger="hover" data-toggle="popover" data-original-title="{$big-q}" data-content="">Interferometer names in abstracts/title/keywords</b>)
        
        let $big-q := $big-q || " - " || $olbin-refereed-q
(:        let $big-query := ( $big-query, " ", adsabs:get-query-link($big-q,<span data-trigger="hover" data-toggle="popover" data-original-title="This query" data-content="exclude OLBIN LIST of the preivous one"> - olbin-refereed</span>) ):)
        let $big-q := $big-q || " - " || $non-interfero-q
(:        let $big-query := ( $big-query, " ", adsabs:get-query-link($big-q,<span data-trigger="hover" data-toggle="popover" data-original-title="This query" data-content="exclude JMMC complimentary LIST of the preivous one"> - jmmc-non-interfero</span>) ):)
        let $big-q := $big-q || " - " || $blacklist-q
        let $big-query := ( $big-query, " =&gt; ",adsabs:get-query-link($big-q,<span><b data-trigger="hover" data-toggle="popover" data-original-title="How to fix ?" data-content="1st add the missing OLBIN in its db 2nd login to ADS and select the ones to be added in olbin-blacklist"> check any missing candidates</b></span>))
        let $q1:=<li>{$big-query}</li>
        
        (: The the big query behind:)
        let $big-q := "property:refereed =full:" || $interferometers
        let $big-query := adsabs:get-query-link($big-q,<b data-trigger="hover" data-toggle="popover" data-original-title="{$big-q}" data-content="">Interferometer names in full text</b>)
        let $big-q := $big-q ||" - abs:(VLTI or CHARA or LBTI or NPOI)"
(:        let $big-query := ( $big-query, " ", adsabs:get-query-link($big-q,<span data-trigger="hover" data-toggle="popover" data-original-title="This query" data-content="exclude the one with abs query"> - VLTI or CHARA in abstracts/title/keywords </span>) ):)
        let $big-q := $big-q || " - " || $olbin-refereed-q
(:        let $big-query := ( $big-query, " ", adsabs:get-query-link($big-q,<span data-trigger="hover" data-toggle="popover" data-original-title="This query" data-content="exclude OLBIN LIST of the preivous one"> - olbin-refereed</span>) ):)
        let $big-q := $big-q || " - " || $non-interfero-q
(:        let $big-query := ( $big-query, " ", adsabs:get-query-link($big-q,<span data-trigger="hover" data-toggle="popover" data-original-title="This query" data-content="exclude JMMC complimentary LIST of the preivous one"> - jmmc-non-interfero</span>) ):)
        let $big-q := $big-q || " - " || $blacklist-q
        let $big-query := ( $big-query, " =&gt; ",adsabs:get-query-link($big-q,<span><b data-trigger="hover" data-toggle="popover" data-original-title="How to fix ?" data-content="1st add the missing OLBIN in its db 2nd login to ADS and select the ones to be added in olbin-blacklist"> check any missing candidates</b></span>))
        let $q2:=<li>{$big-query}</li>
            
            return <p>{($q1, $q2)}</p>
        }</ol>
   </div>
};

declare function app:blacklist-summary($node as node(), $model as map(*)) {
    <div>
        <p>This list sort out some papers retrieved automatically but kept in blacklist so we can ignore them during operations. It is present on {adsabs:get-query-link(adsabs:library-get-search-expr($app:LIST-OLBIN-BLACKLIST), "ADS")} so each own can feed it easily. Its counterpart is also on this db side so we can group them. (We can imagine to provide multiple ads bibcode lists and merge automaticall ???) </p>
        <p>
    Some bibstem are currently ignored:
    <ul>
        {
            for $b in $adsabs:filtered-journals return <li>{data($b)}</li>
        }
        </ul>
    </p>
    <p>{app:show-ads-lists("olbin-blacklist")}</p>
        
    <p>{app:check-updates($node, $model)}</p>
    </div>
};

declare function app:blacklist-list($node as node(), $model as map(*)) {
    let $blacklist-bibcodes := data(adsabs:library-get-bibcodes($app:LIST-OLBIN-BLACKLIST))
    let $blacklist-xml-bibcodes := data($app:blacklist-doc//bibcode)
    return 
        <ul>
            <li>{app:badge("ADS",adsabs:get-libraries()?libraries?*[?name=$app:LIST-OLBIN-BLACKLIST ]?num_documents, $app:ADS-COLOR)}, {app:badge("XML",count($blacklist-xml-bibcodes), $app:OLBIN-COLOR)}</li>
            <li> Curated :<ul>{
              for $group in $app:blacklist-doc//group
                return <li>{data($group/description)}<ul class="list-inline"> {for $bibcode in $group/bibcode return <li>{adsabs:get-link($bibcode,())}</li>} </ul></li>
            }</ul></li>
            <li> Uncurated (i.e. only present onto ADS) :<ul>{
              for $bibcode in $blacklist-bibcodes[not(.=$blacklist-xml-bibcodes)]
                return <li>{adsabs:get-link($bibcode,())}</li>
            }</ul></li>
        </ul>
};

declare function app:is-blacklisted($bibcode){
    $app:blacklist-doc//bibcode=$bibcode
};



declare function app:author-references($node as node(), $model as map(*), $author as xs:string*) {
    
    let $jmmc-groups := $app:jmmc-doc//group[@tag]
    let $jmmc-groups-bibcodes := data($jmmc-groups/bibcode)
    
    let $jmmc-papers-bibcodes := data(adsabs:library-get-bibcodes($app:LIST-JMMC-PAPERS))
    let $base-query := "( " || string-join( ($app:jmmc-doc/jmmc/query) , " or " ) || " ) "
    
    let $groups := 
        for $group in $jmmc-groups
            let $tag := data($group/@tag)
            let $records := adsabs:get-records($group/bibcode)
            
            let $q := string-join($group/bibcode , " or ")
            let $q := if($q) then "( citations(identifier:("||$q||")) )" else ()
            let $citations-link := if($q) then adsabs:get-query-link($q,"view all citations on ADS") else ()
            let $q := string-join((data($q), "( " || $base-query || ' and full:"' || lower-case($group/@tag) ||'" )' )," or ")
            let $citations-link := ($citations-link, adsabs:get-query-link($q," + keywords "))
            
            let $ol := for $record in $records
                let $authors := adsabs:get-authors($record)
                where $authors[contains( ., $author, "?lang=en-US&amp;strength=primary")] 
                let $bibcode := adsabs:get-bibcode($record)
                let $year := adsabs:get-pub-date($record)
                order by $year descending
                return
                    <li>{adsabs:get-html($record, 3),<br/>,string-join(("",adsabs:get-doi($record)), "DOI: ") }</li>
            let $show-citations := ( $ol or $tag = ("OImaging", "OIFitsExplorer", "") ) and not($tag=("Others"))
            
            let $cit-records := if($show-citations) then
                let $bibcodes := adsabs:search($q, "bibcode")?response?docs?*?bibcode
                return adsabs:get-records($bibcodes[not (.=$group/bibcode)])
                else
                    ()
            let $cit-ol := for $record in $cit-records
                let $authors := adsabs:get-authors($record)
                let $bibcode := adsabs:get-bibcode($record)
                let $year := adsabs:get-pub-date($record)
                order by $year descending
                return
                    <li>{adsabs:get-html($record, 3)}</li>
                    
            let $title := $group/description
        return if($ol or $cit-ol) then
                <div>
                
                <h2>Concepteur et responsable <b data-toggle="popover" data-trigger="hover" data-original-title="{$title}" data-content="">{$tag}</b> :</h2>
                {if ($ol) then <div><h3>Co-auteur des publications {$tag}</h3><ul>{$ol}</ul></div> else ()}
                {if ($cit-ol) then <div><h3>Publications citant le logiciel:</h3><ol>{$cit-ol}</ol></div> else ()}
                </div>
                else ()
    
    let $groups := $groups[name()="div"]
        
    return (<ul class="list-group">{$groups}</ul>)
};


declare function app:search-cats($node as node(), $model as map(*)) {
    <ul class="list-inline">
        {
            for $g in $app:jmmc-doc//group[@tag] return <li>{data($g/@tag)}</li>
        }
    </ul>
};

declare function app:search-cats-analysis($node as node(), $model as map(*)) {
    let $sync-lists := try {app:sync-lists()} catch * {()}
    let $refresh := app:check-updates($node, $model)
    
    let $log := util:log("info","app:search-cats-analysis()/1")
    let $jmmc-groups := $app:jmmc-doc//group[@tag and not(@tag='Others')]
    let $jmmc-groups-bibcodes := data($jmmc-groups/bibcode)
    
    let $log := util:log("info","app:search-cats-analysis()/3")
    let $olbin-refereed-q := adsabs:library-get-search-expr($app:LIST-OLBIN-REFEREED)
    let $non-interfero-q := adsabs:library-get-search-expr($app:LIST-NON-INTERFERO)
    let $blacklist-q := "( " || adsabs:library-get-search-expr($app:LIST-OLBIN-BLACKLIST) || " OR bibstem:(" || string-join($adsabs:filtered-journals, " OR ") || ") )"

    let $log := util:log("info","app:search-cats-analysis()/5")
    let $base-query := " full:(&quot;interferometer&quot; or &quot;interferometry&quot;) NOT fulltext_mtime:[&quot;" || current-dateTime() || "&quot; TO *] property:refereed - " || $olbin-refereed-q || " - " || $blacklist-q ||" - " || $non-interfero-q || " "
    let $jmmc-query := " ( " || string-join( ($app:jmmc-doc/jmmc/query) , " or " ) || " ) "
    
    let $groups := map:merge((
        for $group in $jmmc-groups
            let $tag := data($group/@tag)
            let $q := string-join($group/bibcode , " or ")
            let $q := if($q) then "( citations(identifier:("||$q||")) )" else ()
            let $cit-q := if($q) then $q else ()
            let $full-q := ' full:"' || lower-case($group/@tag) ||'"'
            let $q := string-join((data($q), "( " || $jmmc-query || ' and' || $full-q ||' )' )," or ")
            let $q := $q || $base-query
            let $res := adsabs:search($q, "bibcode")
            return
                map:entry($tag, map{"q":$q, "cit-q":$cit-q, "full-q":$full-q, "bibcodes":$res?response?docs?*?bibcode, "numFound":$res?response?numFound, "color":"warning"} )
        ,        
        util:log("info","app:search-cats-analysis()/6")
        ,
        map:for-each(app:get-interferometers(), function ($tag, $q){
            let $q := '=full:('|| string-join($q ! concat('"',.,'"'), " OR ") || ')'
            let $sub-q := $q
            let $q := $q || $base-query
            let $res := adsabs:search($q, "bibcode")
            return
                map:entry($tag, map{"q":$q , "tag-q":$sub-q, "bibcodes":$res?response?docs?*?bibcode, "numFound":$res?response?numFound, "color":"success" })
            })
        ))
        
    let $log := util:log("info","app:search-cats-analysis()/7")
    let $group-list := <ul class="list-inline"> {map:for-each( $groups, function ($key, $value) { <li>
        { adsabs:get-query-link($value?q, app:badge(<span title="{$value?q}">{$key}</span>,$value("numFound"), $value("color"))) } </li> } ) } </ul>
    
    (: pre-load in a single stage :)
    let $bibcodes := distinct-values($groups?*?bibcodes)
    let $records := adsabs:get-records($bibcodes)
    
    let $log := util:log("info","app:search-cats-analysis()/8")
    let $by-bib-list := for $bibcode in subsequence($bibcodes,1,50) order by $bibcode descending
        let $record := adsabs:get-records($bibcode)
        let $tags := for $t in map:keys($groups) return if ( $groups($t)?bibcodes[. = $bibcode] ) then $t else ()
        let $labels := $tags ! ( <li><span class="label label-{$groups(.)?color}">{data(.)}</span></li> )
        let $olbin-add-link := "http://jmmc.fr/bibdb/addPub.php?bibcode=" || encode-for-uri($bibcode) || string-join(("", (for $t in $tags return "tag[]="||$t )), "&amp;") 
        return 
            <li>{adsabs:get-html($record, 3)}
                <ul class="list-inline">
                    <li><a target="_blank" href="{$olbin-add-link}">Add article to OLBIN</a>&#160;</li>
                    { $labels }
                </ul>
            </li>
    
    let $log := util:log("info","app:search-cats-analysis()/9")
    let $jmmc-tags-query := $jmmc-query || " and ( " || string-join( ( ($groups?*?full-q) ! concat( '(', ., ')' ) ) , " or ") || " ) "
    let $global-query := $base-query || "(" || string-join(( $groups?*?tag-q, $groups?*?cit-q , $jmmc-tags-query), ") or (") || ")"
    let $global-link := adsabs:get-query-link($global-query , "View this list on ADS", "sort=bibcode")
    
    let $log := util:log("info","app:search-cats-analysis()/11")
    return ( $refresh, $group-list, <h2>{count($by-bib-list)}/{count($bibcodes)} publications to filter and review ({$global-link})</h2>,  <ol>{$by-bib-list}</ol> )
};

declare function app:check-tags-analysis($node as node(), $model as map(*)) {
    
    let $log := util:log("info","app:check-tags-analysis()/1")
    let $sync-lists := try {app:sync-lists()} catch * {()}
    
    let $max := request:get-parameter("max", 50)
    
    let $jmmc-groups := $app:jmmc-doc//group[@tag and not(@tag='Others')]
    let $jmmc-groups-bibcodes := data($jmmc-groups/bibcode)
    
    let $log := util:log("info","app:check-tags-analysis()/2")
    
    let $olbin-doc := app:get-olbin()
    
    let $olbin-refereed-q := adsabs:library-get-search-expr($app:LIST-OLBIN-REFEREED)
    let $non-interfero-q := adsabs:library-get-search-expr($app:LIST-NON-INTERFERO)
    let $blacklist-q := "( " || adsabs:library-get-search-expr($app:LIST-OLBIN-BLACKLIST) || " OR bibstem:(" || string-join($adsabs:filtered-journals, " OR ") || ") )"
    
    let $log := util:log("info","app:check-tags-analysis()/5")
    
    let $base-query := " " || $olbin-refereed-q || " - docs(library/evb9oMKNQNStAy66cyKtJg) "
    let $jmmc-query := " ( " || string-join( ($app:jmmc-doc/jmmc/query) , " or " ) || " ) "
    
    let $groups := map:merge((
        for $group in $jmmc-groups
            let $tag := data($group/@tag)
            let $q := string-join($group/bibcode , " or ")
            let $q := if($q) then "( citations(identifier:("||$q||")) )" else ()
            let $cit-q := if($q) then $q else ()
            let $full-q := ' full:"' || lower-case($group/@tag) ||'"'
            let $q := string-join((data($q), "( " || $jmmc-query || ' and' || $full-q ||' )' )," or ")
            let $q := $q || $base-query
            let $res := adsabs:search-bibcodes($q)
            return
                map:entry($tag, map{"q":$q, "cit-q":$cit-q, "full-q":$full-q, "bibcodes":$res, "numFound":count($res), "color":"warning"} )
        ,        
        util:log("info","app:check-tags-analysis()/6")
        ,
        map:for-each(app:get-interferometers(), function ($tag, $q){
            let $q := '=full:('|| string-join($q ! concat('"',.,'"'), " OR ") || ')'
            let $sub-q := $q
            let $q := $q || $base-query
            let $res := adsabs:search-bibcodes($q)
            return
                map:entry($tag, map{"q":$q , "tag-q":$sub-q, "bibcodes":$res, "numFound":count($res), "color":"success" })
            })
        ))
        
    let $log := util:log("info","app:check-tags-analysis()/7")
    
    let $group-list := <ul class="list-inline"> {map:for-each( $groups, function ($key, $value) { <li>
        { adsabs:get-query-link($value?q, app:badge(<span title="{$value?q}">{$key}</span>,$value("numFound"), $value("color"))) } </li> } ) } </ul>
    
    
    let $bibcodes := distinct-values($groups?*?bibcodes)
    
    let $ok-bib-list := for $bibcode in $bibcodes
        let $tags := for $t in map:keys($groups) return if ( $groups($t)?bibcodes[. = $bibcode] ) then 
            if($olbin-doc//e[bibcode=$bibcode]/tag=$t) then () (: we may show that it is already tagged ? :) else $t
            else ()
        where empty($tags)
        return $bibcode
    let $store-in-ads := adsabs:library-add("olbin-tag-reviewed", $ok-bib-list)
    
    let $bibcodes-to-analyse := $bibcodes[not(.=$ok-bib-list)]
    
    (: pre-load in a single stage only first one - this may be long :)
    let $bibcodes-to-display := subsequence($bibcodes-to-analyse,1,$max)
    let $records := adsabs:get-records($bibcodes-to-display)
    
    let $by-bib-list := for $bibcode in $bibcodes-to-display order by $bibcode descending
        let $tags := for $t in map:keys($groups) return if ( $groups($t)?bibcodes[. = $bibcode] ) then 
            if($olbin-doc//e[bibcode=$bibcode]/tag=$t) then () (: we may show that it is already tagged ? :) else $t
            else ()
        where exists($tags) 
        let $record := adsabs:get-records($bibcode)
        let $labels := $tags ! ( <li class="candidate-tag"><span class="label label-{$groups(.)?color}">{data(.)}</span></li> )
        let $olbin-add-link := "http://jmmc.fr/bibdb/updatePubs.php?filter=" || encode-for-uri($bibcode) || string-join(("", (for $t in $tags return "tag[]="||$t )), "&amp;") 
        return 
            <li class="pubtags ">{adsabs:get-html($record, 3)}
                <ul class="list-inline">
                    <li><button id="{$bibcode}" class="flagtag btn btn-default">Flag tag review</button> / <a class="btn btn-default" target="_blank" href="{$olbin-add-link}">update OLBIN's tags</a>&#160;</li>
                    { $labels } 
                    <!--<form action="https:ui.adsabs.harvard.edu/v1/biblib/documents/p4drdURkRnqKPBWx6zJ-pA" method="POST"><input type="hidden" name="action" value="add"/><input type="hidden" name="bibcode" value="{$bibcode}"/><button>Tag OK / hide me</button></form>-->
                    
                    
                </ul>
            </li>
    
    let $jmmc-tags-query := $jmmc-query || " and ( " || string-join( ( ($groups?*?full-q) ! concat( '(', ., ')' ) ) , " or ") || " ) "
    let $global-query := $base-query || "(" || string-join(( $groups?*?tag-q, $groups?*?cit-q , $jmmc-tags-query), ") or (") || ")"
    let $global-link := adsabs:get-query-link($global-query , "View this list on ADS", "sort=bibcode")
    
    let $script := <script>
        <![CDATA[
        $( 'body' ).on( 'click', '.flagtag', function(event) {   
            $.ajaxSetup({traditional: true});
            var bibcode = $(this).attr("id");
            var answer = confirm('Are you sure you want to leave proposed tags unchecked for "'+bibcode+'" paper ?');
            if (answer)
            {
                var li = $(this).parents(".pubtags");
                var tags = [];
                li.find(".candidate-tag").each(function(){tags.push($(this).text());});

                $.ajax( { url: "/exist/restxq/add-to-library/olbin-tag-reviewed",  data: { bibcodes: bibcode, tags: tags} } )
                .done(function() { li.remove(); })
                .fail(function() { alert( "Sorry can't process your request, please Sign In first" ); });
            }
        });            
        ]]>
    </script>

    
    let $log := util:log("info","app:check-tags-analysis()/11")
    return ( $group-list, <h2>{count($by-bib-list)} publications need a tag update. {$max} tested over <a href="?max={count($bibcodes-to-analyse)}">{count($bibcodes-to-analyse)}</a> to be reviewed ({$global-link})</h2>,  <ol>{$by-bib-list}</ol>, $script )
};


(:  to avoid massive updates we can just compute list counts and update differences only  :)
declare function app:check-update($libraries, $list-name, $bibcodes as xs:string*, $skip-cache-flush as xs:boolean){
    let $ads-list := $libraries?libraries?*[?name=$list-name]
    let $num_documents := number($ads-list?num_documents)
    let $count := number(count($bibcodes))
    let $do-update := if( $count = $num_documents ) then false() else true()
    return 
        if ( count($bibcodes)=$num_documents ) 
        then ()
(:        $list-name || " uptodate" :)
        else
            let $log  := util:log("info", string-join(("check-updates for",$list-name, "got", $num_documents, "vs", $count)," " ))
            let $log := if( $skip-cache-flush ) then () else util:log("info", "changed required => clear adsabs cache")
            let $clear-cache :=  if( $skip-cache-flush ) then () else cache:clear($adsabs:expirable-cache-name)
            let $id := $ads-list?id
            let $ads-bibcodes:= data(adsabs:search("docs(library/"||$id||")", "bibcode")?response?docs?*?bibcode)
            let $missings := $bibcodes[not(.=$ads-bibcodes)]
            let $outdated := $ads-bibcodes[not(.=$bibcodes)]
            let $update-a := if(true() and exists($missings)) then adsabs:library-add($id, $missings) else ()
            let $update-r := if(exists($outdated)) then adsabs:library-remove($id, $outdated) else ()
            (: todo after insert in olbin-refereed : remove all new ones from olbin-missings :)
            return 
            ($update-a, $update-r,$list-name || " need sync (olbin db:" || count($bibcodes) || ", ads:" ||  $num_documents|| ") : missing are "|| string-join($missings, " OR ") || ", outdated are "|| string-join($outdated, " OR ") )
};

declare function app:sync-lists(){
let $clear-olbin := cache:remove($app:expirable-cache-name, "olbin-xml")

let $force-clear := if(false()) then cache:clear($adsabs:expirable-cache-name) else ()

let $entries :=  app:get-olbin()//e
let $bibcodes := $entries//bibcode
let $fresh-libraries := adsabs:get-libraries(false())
let $existing-lib-names := data($fresh-libraries?libraries?*?name)

let $res := () (: stack results :)

let $main-updates := app:check-update($fresh-libraries, "olbin-refereed", $bibcodes, false())

let $res := ($res , $main-updates)

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
let $res := ($res , app:check-update($fresh-libraries, "telbib-vlti", $telbibcodes, false()))
 

let $res := ( $res, for $tag in app:get-olbin()/publications/tag
        let $bibcodes := $entries[tag=$tag]/bibcode
        let $list-name := "tag-olbin "||$tag
        where $list-name = $existing-lib-names
        return app:check-update($fresh-libraries, $list-name, $bibcodes, false())
    )
    
let $clear-libraries := cache:remove($adsabs:expirable-cache-name, "/biblib/libraries")
let $ask-again := adsabs:get-libraries()

return <pre>{$res}</pre>
};

(:return adsabs:get-libraries()?libraries?*[?name='olbin-refereed']:)
(:for $list in $existing-lib-names:)
(:    return $list:)
(:return  count($entries//e) = $num_documents:)

