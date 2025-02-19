xquery version "3.1";

module namespace app="http://olbin.org/exist/bibdb/templates";

import module namespace templates="http://exist-db.org/xquery/templates" ;
import module namespace config="http://olbin.org/exist/bibdb/config" at "config.xqm";
import module namespace adsabs="http://exist.jmmc.fr/jmmc-resources/adsabs" at "/db/apps/jmmc-resources/content/adsabs.xql";
import module namespace jmmc-auth="http://exist.jmmc.fr/jmmc-resources/auth";
import module namespace jmmc-dateutil="http://exist.jmmc.fr/jmmc-resources/dateutil" at "/db/apps/jmmc-resources/content/jmmc-dateutil.xql";
import module namespace jmmc-tap="http://exist.jmmc.fr/jmmc-resources/tap";


import module namespace kwic="http://exist-db.org/xquery/kwic";


import module namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace rest="http://exquery.org/ns/restxq";

declare namespace ads="https://ads.harvard.edu/schema/abs/1.1/abstracts";

(:declare variable $app:olbin-doc := doc($config:data-root||"/olbin.xml"); replace by app:get-olbin:)
declare variable $app:jmmc-doc := doc($config:data-root||"/jmmc.xml");
declare variable $app:curation-doc := doc($config:data-root||"/curation.xml")/*;
declare variable $app:blocklist-doc := doc($config:data-root||"/blocklists.xml");
(:declare variable $app:journal-names-doc := doc($config:data-root||"/journal-names.xml");:)
 declare variable $app:journal-names-doc := doc("/db/apps/bibdb-data/data/journal-names.xml");
(: declare variable $app:ads-journals := doc($config:data-root||"/ads-journals.xml")//journal;:)
 declare variable $app:ads-journals := doc("/db/apps/bibdb-data/data/ads-journals.xml")//journal;


declare variable $app:LIST-JMMC-PAPERS  := "jmmc-papers";
declare variable $app:LIST-JMMC-OIDB  := "oidb-pubs";
declare variable $app:LIST-NON-INTERFERO  := "jmmc-non-interfero";
declare variable $app:LIST-OLBIN-REFEREED := "olbin-refereed";
declare variable $app:LIST-OLBIN-TAG-REVIEWED := "olbin-tag-reviewed";
declare variable $app:LIST-OLBIN-TAG-CURATED := "olbin-tag-curated";

declare variable $app:LIST-OLBIN-BLOCKLIST := "olbin-blocklist";
declare variable $app:LIST-OLBIN-CANDIDATES := "olbin-candidates";

declare variable $app:ADS-COLOR := "primary";
declare variable $app:OLBIN-COLOR := "success";

declare variable $app:expirable-cache-name :="bibdbmgrcache";
declare variable $app:expirable-cache := cache:create($app:expirable-cache-name,map { "expireAfterAccess": 300000 }); (: 5min :)

declare variable $app:telbib-vlti-url := "https://telbib.eso.org/api.php?telescope[]=vlti+visitor&amp;telescope[]=vlti";


declare function app:plots($node as node(), $model as map(*)){
<script src='https://cdn.plot.ly/plotly-2.26.0.min.js'></script>,
<div id="myDiv"/>,
let $olbin := app:get-olbin()
let $a-tags := sort( $olbin//category[name="Astrophysical topic"]//tag )

let $min-bibcode-count := 50

let $log := util:log("info", "prepare data")
let $tag-map := map:merge(
    for $t in $olbin//e/tag group by $tag := data($t)
    where $tag=$a-tags
    let $bibcodes := data($t/../bibcode)
    where count($bibcodes)>$min-bibcode-count
    return map:entry($tag, $bibcodes)
    )
let $log := util:log("info", "tag map done")

let $records := adsabs:get-records($olbin//bibcode)
(:
 let $keywords-bibcodes := map:merge(
    for $k in $records//ads:keyword group by $kw := replace(lower-case($k), "[^a-zA-Z :]","")
        return map:entry($kw, data($k/../ads:bibcode))
    )
let $keywords := map:keys($keywords-bibcodes)
:)
let $keywords := for $k in $records//ads:keyword group by $kw := replace(lower-case($k), "[^a-zA-Z :]","")
        return data($kw)

let $kw-map := map:merge(
    for $k in $records//ads:keyword group by $kw := replace(lower-case($k), "[^a-zA-Z :]","")
    let $bibcodes := data($k/../../ads:bibcode)
    where count($bibcodes)>$min-bibcode-count
    return
        map:entry($kw, $bibcodes )
    )


let $log := util:log("info", "kw map done")

(:
let $log := for $kw in map:keys($kw-map)
        let $kw-bibcodes := map:get($kw-map, $kw)
        return util:log("info", "kw  "|| $kw || " has " || count($kw-bibcodes))
:)

let $tag-keys := for $tag in map:keys($tag-map)
        let $tag-bibcodes := map:get($tag-map, $tag)
        order by count($tag-bibcodes) descending
        return $tag
let $kw-keys := for $kw in map:keys($kw-map)
                let $kw-bibcodes := map:get($kw-map, $kw)
                order by count($kw-bibcodes) descending
                return $kw

let $z :=
        for $tag in $tag-keys
        let $tag-bibcodes := map:get($tag-map, $tag)
        let $toto :=
        for $kw in $kw-keys
        let $kw-bibcodes := map:get($kw-map, $kw)

            return count($tag-bibcodes[.=$kw-bibcodes])
        return
            "[" || string-join($toto,"," ) || "]"
let $log := util:log("info", " z done")


return
    <script>
    var data = [
    {{
        z: [{string-join($z, ",&#10;")}],
        x: [{string-join($tag-keys ! concat("'", ., "'"), ", ")}],
        y: [{string-join($kw-keys ! concat("'", ., "'"), ", ")}],

        type: 'heatmap',
    }}
    ];
    var layout = {{
        title: 'ADS keywords vs Astrophysical results tags {count($tag-keys)}x{count($kw-keys)}',
        width: 1000,
        height: 1000,
        xaxis: {{visible: false}},
        yaxis: {{visible: false}},
    }};

    Plotly.newPlot('myDiv', data, layout);
    </script>

};



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
    let $last-ads-mod-date := max($ads-libraries?libraries?*?date_last_modified)
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
    let $id := adsabs:get-libraries()?libraries?*[?public=true() and ?name[.=$app:LIST-OLBIN-REFEREED] ]?id
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
    <p>Welcome on the OLBIN  publications management area. <a href="https://publications.olbin.org/">Visit the current portal.</a>
    <br/> This web area is a <b>*work in progress*</b>.
    <br/>Main goals are:
    <ul>
        <li>Improve tools to meter publications related to OLBIN and it&apos;s sublists taking advantage of tagging provided by the content tracker (Alain Chelli).</li>
        <li>Keep OLBIN paper list up to date taking advantage of the nice <a href="https://ui.adsabs.harvard.edu">NASA/ADS</a> API.</li>
    </ul>
    <br/>{map:get($model,"olbin-nb-pubs")} OLBIN publications (last update on {map:get($model,"date-last-olbin-update")} , last ads list synchronization on {map:get($model,"date-last-ads-update")}).
    <br/>Please contact the <a href="http://www.jmmc.fr/support">jmmc user support</a> for any remark, question or idea. Directions to enter the collaborative mode should come ...
    </p>
};





declare function app:others-lists($node as node(), $model as map(*)) {
    let $jmdc-csv-libname := 'jmdc-csv'
    let $jmdc-csv-interfero-libname := 'jmdc-csv-interfero'

    let $olbin-stellar-diameters-libname := "tag-olbin Stellar diameters"


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
    let $q14 := adsabs:library-query($olbin-stellar-diameters-libname) || " " || $q11
    let $q15 := " - " || $q14

    let $q21 := adsabs:library-query($olbin-stellar-diameters-libname)
    let $q22 := $q21 || " " || $q11
    let $q23 := $q21 || " - " || $q11

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
                <li>{adsabs:get-query-link($q21,"Olbin.Stellar diameters")} : {data(adsabs:get-libraries()?libraries?*[?name=$olbin-stellar-diameters-libname]?num_documents)} bibcodes
                    <ul><li> {adsabs:get-query-link($q22," part of JMDC/interfero")}</li><li> {adsabs:get-query-link($q23,<b> not part of JMDC/interfero</b>)}</li></ul>
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
(:    app:show-ads-lists('jmdc-csv-interfero'),:)
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
        let $list-to-ignore := ('olbin-candidates', 'olbin-tag-reviewed',"olbin-blocklist")
        let $new := adsabs:get-libraries(false()) (: force refresh :)
        let $new-last-modification := max($new?libraries?*[not(.?name=$list-to-ignore)]?date_last_modified)
        let $old-last-modification := max($old?libraries?*[not(.?name=$list-to-ignore)]?date_last_modified)
        let $olbin-last-modification := max(app:get-olbin()//e/subdate/string())
        let $info := <ul><li>Last ADS change (blocklist ignored) : {$new-last-modification}</li><li>Last OLBIN change : {$olbin-last-modification}</li></ul>
        return if( $new-last-modification > $old-last-modification or $olbin-last-modification > $new-last-modification ) then
            ( util:log("info", "update required"), cache:clear($adsabs:expirable-cache-name) (: clear caches... :)
            ,<div class="alert alert-warning fade in">
                    <button type="button" class="close" data-dismiss="alert" aria-hidden="true">×</button>
                    <strong>Sorry for the additional delay!</strong> The lists just have been synchronized with ADS.<br/>
                    {$info}
                </div>
            )
            else
                (  util:log("info", "we seem uptodate, ADS:"||$new-last-modification ||"  ,OLBIN:"||$olbin-last-modification),
                    <div class="alert alert-success fade in">
                        <button type="button" class="close" data-dismiss="alert" aria-hidden="true">×</button>
                        The lists do not require to be updated on ADS.<br/>
                        {$info}
                    </div>
                )
        else () (: nothing to do : next call will come later, this avoid 2 calls instead of 1 :)
};



declare function app:hierarch-tags($node as node(), $model as map(*)) {
    let $olbin-doc := app:get-olbin()
    let $childrens := map {
        "JMMC": data($olbin-doc//category[name="HIDDEN"]/tag)
        ,'SUSI' : ('PAVO')
        ,'VLTI' : ('GRAVITY', 'AMBER', 'MIDI', 'PIONIER', 'VINCI', 'PRIMA', 'MATISSE', 'ASGARD')
        ,'AAT' : ('MAPPIT')
        ,'LBTI' : ('LMIRCam', 'NOMIC', 'PEPSI', 'ALES')
        ,'CHARA' : ('CHARA', 'MIRC', 'VEGA', 'PAVO', 'CLIMB', 'VEGA Friend', 'SPICA', 'MIRC-X', 'MYSTIC')
        ,'SUBARU' : ('GLINT')
        ,'VLT' : ('SPHERE')
        ,'JWST' : ('AMI')
        ,'NPOI' : ('VISION')
    }
    let $parents := map:merge(
        map:for-each($childrens, function($k, $vs){ for $v in $vs where $v!=$k return map:entry($v, $k) } )
    )

    let $to-fix := for $e in reverse($olbin-doc//e)
        let $current-tags := for $tag in $e/tag return $tag
        let $missing-tags := for $t in map:keys($parents)[.=$current-tags]
            let $c := map:get($parents, $t)
            where not($c=$current-tags)
            let $log := util:log("info", $t || " ask for missing tags "||$c || " : " || ($c=$current-tags))
            return
                $c
        let $missing-tags := distinct-values($missing-tags)
        where exists($missing-tags)
        let $record := adsabs:get-records($e/bibcode)
        let $tags := for $tag in $current-tags return <li><span class="label label-default">{$tag}</span></li>
        return
            <div class="panel panel-default">
                <div class="panel-heading">{adsabs:get-html( $record , 3 )}</div>
                <div class="panel-body">
                <ul class="list-inline">{$tags}<br/>add missing tags ? <br/>{$missing-tags}</ul>
                </div>
            </div>
    return
        $to-fix
};

declare function app:jmmc-references($node as node(), $model as map(*)) {
    let $jmmc-groups := $app:jmmc-doc//group[@tag]
    let $jmmc-groups-bibcodes := data($jmmc-groups/bibcode)

    let $olbin-doc := app:get-olbin()
    let $olbin-bibcodes := data($olbin-doc//bibcode) (: could be ads list ? :)
    let $non-interfero-bibcodes := data(adsabs:library-get-bibcodes($app:LIST-NON-INTERFERO))
    let $blocklist-bibcodes := data(adsabs:library-get-bibcodes($app:LIST-OLBIN-BLOCKLIST))
    let $jmmc-papers-bibcodes := data(adsabs:library-get-bibcodes($app:LIST-JMMC-PAPERS))

    let $olbin-refereed-q := adsabs:library-get-search-expr($app:LIST-OLBIN-REFEREED)
    let $non-interfero-q := adsabs:library-get-search-expr($app:LIST-NON-INTERFERO)
    let $blocklist-q := "( " || adsabs:library-get-search-expr($app:LIST-OLBIN-BLOCKLIST) || " OR bibstem:(" || string-join($adsabs:filtered-journals, " OR ") || ") )"


    (: Higlight jmmc-papers and blocklist present on ADS and missing in the xml db :)
(:    let $missing-in-blocklist := for $record in adsabs:get-records($jmmc-papers-bibcodes[not(.=$jmmc-groups-bibcodes)]) return <li>&lt;!--{adsabs:get-title($record)}--&gt;<br/>{ serialize(<bibcode>{adsabs:get-bibcode($record)}</bibcode>)} </li>:)
(:    let $missing-in-groups := if($missing-in-groups) then <div><h4>ADS jmmc-papers not present in local db</h4><ul> {$missing-in-groups}</ul></div> else ():)

    let $missing-jmmc-papers-bibcodes := $jmmc-groups-bibcodes[not(.=$jmmc-papers-bibcodes)]
    let $missing-jmmc-papers := if(exists($missing-jmmc-papers-bibcodes)) then "identifier:("|| string-join($missing-jmmc-papers-bibcodes, ' or ')||")" else ()
    let $missing-jmmc-papers := if($missing-jmmc-papers) then adsabs:get-query-link($missing-jmmc-papers,"Please add next jmmc-papers in ADS") else ()
(:        <div><h4>ADS jmmc-papers contains all xmldb papers</h4></div>:)


    let $missing-in-groups := for $record in adsabs:get-records($jmmc-papers-bibcodes[not(.=$jmmc-groups-bibcodes)]) return <li>&lt;!--{adsabs:get-title($record)}--&gt;<br/>{ serialize(<bibcode>{adsabs:get-bibcode($record)}</bibcode>)} </li>
    let $missing-in-groups := if($missing-in-groups) then <div><h4>ADS jmmc-papers not present in local db</h4><ul> {$missing-in-groups}</ul></div> else ()
(:        <div><h4>ADS jmmc-papers present in local db</h4></div>:)


    (: The the big query behind:)

    let $base-query := "( " || string-join( ($app:jmmc-doc/jmmc/query) , " or " ) || " ) "
    let $big-q := "( " || $base-query || " and full:( " ||string-join( ($jmmc-groups/@tag[not(.='tbd')], $jmmc-groups//q ) , " or ") || ") ) or ( citations(identifier:(" || string-join( $jmmc-groups-bibcodes , " or ") || ")) )"
    let $big-query := adsabs:get-query-link($big-q,<b data-trigger="hover" data-toggle="popover" data-original-title="This query" data-content="is a naïve one on top of the citations of jmmc papers and some full text query on top of associated kaywords">Global search</b>)
    let $big-q := $big-q || " - " || $olbin-refereed-q
(:    let $big-query := ( $big-query, " ", adsabs:get-query-link($big-q,<span data-trigger="hover" data-toggle="popover" data-original-title="This query" data-content="exclude OLBIN LIST of the preivous one"> - olbin-refereed</span>) ):)
    let $big-q := $big-q || " - " || $non-interfero-q
(:    let $big-query := ( $big-query, " ", adsabs:get-query-link($big-q,<span data-trigger="hover" data-toggle="popover" data-original-title="This query" data-content="exclude JMMC complimentary LIST of the preivous one"> - jmmc-non-interfero</span>) ):)
    let $big-q := $big-q || " - " || $blocklist-q
    let $big-query := ( $big-query, " =&gt; ",adsabs:get-query-link($big-q,<span><b data-trigger="hover" data-toggle="popover" data-original-title="How to fix ?" data-content="1st add the missing OLBIN in its db 2nd login to ADS and select the ones to be added in jmmc-non-interfero or olbin-blocklist lists"> check any missing candidates</b></span>))
    let $big-query := <p>{( <span>{$big-query}</span>)}</p>


    let $legend := <p><i class="text-success glyphicon glyphicon-ok-circle"/> present in OLBIN, <i class="text-warning glyphicon glyphicon-plus-sign"/> missing , <i class="glyphicon glyphicon-ban-circle"/> non refereed (or SPIE, ASCS), <i class="glyphicon glyphicon-bookmark"/> non-interfero, <s>blocklisted</s>  </p>

    let $groups :=
        for $group in $jmmc-groups
            let $tag := data($group/@tag)
            let $records := adsabs:get-records($group/bibcode)
            let $q := string-join($group/bibcode , " or ")
            let $q := if($q) then "( citations(identifier:("||$q||")) )" else ()
            let $citations-link := if($q) then adsabs:get-query-link($q,"view all citations on ADS") else ()
            let $full-q := ' full:(' || string-join(($group/@tag,$group/q) ! concat('"',lower-case(.),'"'), " OR ") ||')'
            let $q := string-join((data($q), "( " || $base-query || ' and ' || $full-q || ' )' )," or ")
            let $citations-link := ($citations-link, adsabs:get-query-link($q," + keywords "))
            let $q := $q || " - " || $olbin-refereed-q
(:            let $citations-link := ($citations-link, adsabs:get-query-link($q," - OLBIN ")):)
            let $q := $q || " property:refereed"
(:            let $citations-link := ($citations-link, adsabs:get-query-link($q," - non-refereed ")):)
            let $q := $q || " - " || $blocklist-q
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
(:                        return <li>{if(app:is-blocklisted($c)) then <s>{$links}</s> else $links}</li>:)
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
(:    "COAST": "COAST", add to many result for earthscience :)
    "GI2T": "GI2T",
    "HYPERTELESCOPES": ("HYPERTELESCOPES","Hypertelescope"),
(:    "I2T": "I2T",:)
    "IACT": "Imaging Atmospheric Cherenkov Telescopes",
(:    "IOTA": "IOTA", indexed because of iota greek :)
    (: "IRMA": "IRMA", :)
(:   "ISI ": "ISI ",:)
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
        let $blocklist-q := "( " || adsabs:library-get-search-expr($app:LIST-OLBIN-BLOCKLIST) || " OR bibstem:(" || string-join($adsabs:filtered-journals, " OR ") || ") )"

        let $interferometers :=  ( map:for-each(app:get-interferometers(), function($k,$v) { $v}) ! concat('"',.,'"') => string-join(" or ") ) ! concat('(',.,')')

        (: The the big query behind:)
        let $big-q := "property:refereed abs:"||$interferometers
        let $big-query := adsabs:get-query-link($big-q,<b data-trigger="hover" data-toggle="popover" data-original-title="{$big-q}" data-content="">Interferometer names in abstracts/title/keywords</b>)

        let $big-q := $big-q || " - " || $olbin-refereed-q
(:        let $big-query := ( $big-query, " ", adsabs:get-query-link($big-q,<span data-trigger="hover" data-toggle="popover" data-original-title="This query" data-content="exclude OLBIN LIST of the preivous one"> - olbin-refereed</span>) ):)
        let $big-q := $big-q || " - " || $non-interfero-q
(:        let $big-query := ( $big-query, " ", adsabs:get-query-link($big-q,<span data-trigger="hover" data-toggle="popover" data-original-title="This query" data-content="exclude JMMC complimentary LIST of the preivous one"> - jmmc-non-interfero</span>) ):)
        let $big-q := $big-q || " - " || $blocklist-q
        let $big-query := ( $big-query, " =&gt; ",adsabs:get-query-link($big-q,<span><b data-trigger="hover" data-toggle="popover" data-original-title="How to fix ?" data-content="1st add the missing OLBIN in its db 2nd login to ADS and select the ones to be added in olbin-blocklist"> check any missing candidates</b></span>))
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
        let $big-q := $big-q || " - " || $blocklist-q
        let $big-query := ( $big-query, " =&gt; ",adsabs:get-query-link($big-q,<span><b data-trigger="hover" data-toggle="popover" data-original-title="How to fix ?" data-content="1st add the missing OLBIN in its db 2nd login to ADS and select the ones to be added in olbin-blocklist"> check any missing candidates</b></span>))
        let $q2:=<li>{$big-query}</li>

            return <p>{($q1, $q2)}</p>
        }</ol>
   </div>
};

declare function app:blocklist-summary($node as node(), $model as map(*)) {
    <div>
        <p>This list sort out some papers retrieved automatically but kept in blocklist so we can ignore them during operations. It is present on {adsabs:get-query-link(adsabs:library-get-search-expr($app:LIST-OLBIN-BLOCKLIST), "ADS")} so each own can feed it easily. Its counterpart is also on this db side so we can group them. (We can imagine to provide multiple ads bibcode lists and merge automaticall ???) </p>
        <p>
    Some bibstem are currently ignored:
    <ul>
        {
            for $b in $adsabs:filtered-journals return <li>{data($b)}</li>
        }
        </ul>
    </p>
    <p>{app:show-ads-lists("olbin-blocklist")}</p>

    <p>{app:check-updates($node, $model)}</p>
    </div>
};

declare function app:blocklist-list($node as node(), $model as map(*)) {
    let $blocklist-bibcodes := data(adsabs:library-get-bibcodes($app:LIST-OLBIN-BLOCKLIST))
    let $blocklist-xml-bibcodes := data($app:blocklist-doc//bibcode)
    return
        <ul>
            <li>{app:badge("ADS",adsabs:get-libraries()?libraries?*[?name=$app:LIST-OLBIN-BLOCKLIST ]?num_documents, $app:ADS-COLOR)}, {app:badge("XML",count($blocklist-xml-bibcodes), $app:OLBIN-COLOR)}</li>
            <li> Curated :<ul>{
              for $group in $app:blocklist-doc//group
                return <li>{data($group/description)}<ul class="list-inline"> {for $bibcode in $group/bibcode return <li>{adsabs:get-link($bibcode,())}</li>} </ul></li>
            }</ul></li>
            <li> Uncurated (i.e. only present onto ADS) :<ul>{
              for $bibcode in $blocklist-bibcodes[not(.=$blocklist-xml-bibcodes)]
                return <li>{adsabs:get-link($bibcode,())}</li>
            }</ul></li>
        </ul>
};

declare function app:is-blocklisted($bibcode){
    $app:blocklist-doc//bibcode=$bibcode
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
            let $full-q := ' full:(' || string-join(($group/@tag,$group/q) ! concat('"',lower-case(.),'"'), " OR ") ||')'
            let $q := string-join((data($q), "( " || $base-query || ' and ' || $full-q || ' )' )," or ")
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

                <h2><b data-toggle="popover" data-trigger="hover" data-original-title="{$title}" data-content="">{$tag}</b> :</h2>
                {if ($ol) then <div><h3>Co-auteur des publications</h3><ul>{$ol}</ul></div> else ()}
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

declare function app:search-cats-analysis($node as node(), $model as map(*), $skip as xs:string?) {
    let $start-one := util:system-time()
    let $sync-lists := try {if(exists($skip)) then () else app:sync-lists(true())} catch * {()}
    let $refresh := if(empty($skip)) then app:check-updates($node, $model) else ()

    let $start-two := util:system-time()

    let $log := util:log("info","app:search-cats-analysis()/1 search groups and their bibcodes")
    let $jmmc-groups := $app:jmmc-doc//group[@tag and not(@tag='Others')]
    let $jmmc-groups-bibcodes := data($jmmc-groups/bibcode)

    let $log := util:log("info","app:search-cats-analysis()/2 prepare main queries (olbin, non-interfero, blocklist)")
    let $olbin-refereed-q := adsabs:library-get-search-expr($app:LIST-OLBIN-REFEREED)
    let $non-interfero-q := adsabs:library-get-search-expr($app:LIST-NON-INTERFERO)
    let $candidates-q := adsabs:library-get-search-expr($app:LIST-OLBIN-CANDIDATES)
    let $blocklist-q := "( " || adsabs:library-get-search-expr($app:LIST-OLBIN-BLOCKLIST) || " OR bibstem:(" || string-join($adsabs:filtered-journals, " OR ") || ") )"

    let $log := util:log("info","app:search-cats-analysis()/3 prepare base query ")
    let $base-query := " year:[2000 TO NOW] -collection:(earthscience)   full:(&quot;interferometer&quot; or &quot;interferometry&quot; or &quot;aperture masking&quot;)fulltext_mtime:[&quot;1000-11-23T14:02:07.762Z&quot; TO *] property:refereed - " || $olbin-refereed-q || " - " || $blocklist-q ||" - " || $non-interfero-q || " "
(:     NOT fulltext_mtime:[&quot;" || current-dateTime() || "&quot; TO *] entdate:[NOW-90DAYS TO NOW] :)


    let $second-order-queries := map {
        "Sparse Aperture Masking (SAM)" : ("aperture masking")
    }


    let $log := util:log("info","app:search-cats-analysis()/4 prepare jmmc query ")
    let $jmmc-query := " ( " || string-join( ($app:jmmc-doc/jmmc/query) , " or " ) || " ) "


    let $log := util:log("info","app:search-cats-analysis()/5 prepare group queries")

    let $groups :=
            map:merge((
            for $group in $jmmc-groups
                let $tag := data($group/@tag)
                let $q := string-join($group/bibcode , " OR ")
                let $q := if($q) then "( citations(identifier:("||$q||")) )" else ()
                let $cit-q := if($q) then $q else ()
                let $full-q := ' full:(' || string-join(($group/@tag,$group/q) ! concat('"',lower-case(.),'"'), " OR ") ||')'
                let $q := string-join((data($q), "( " || $jmmc-query || ' AND' || $full-q ||' )' )," OR ")
                let $quickq := $candidates-q || ' ' || $q
                let $q := $q || $base-query
                return
                    map:entry($tag, map{"q":$q, "quickq":$quickq, "cit-q":$cit-q, "full-q":$full-q, "color":"warning"} )
            ,
            map:for-each(app:get-interferometers(), function ($tag, $q){
                let $q := '=full:('|| string-join($q ! concat('"',.,'"'), " OR ") || ')'
                let $sub-q := $q
                let $quickq := $candidates-q || ' ' || $q
                let $q := $q || $base-query
                return
                    map:entry($tag, map{"q":$q, "quickq":$quickq, "tag-q":$sub-q, "color":"success" })
                })
            ))

    let $log := util:log("info","app:search-cats-analysis()/6 prepare main query and subqueries")
    let $jmmc-tags-query := $jmmc-query || " and ( " || string-join( ( ($groups?*?full-q) ! concat( '(', ., ')' ) ) , " or ") || " ) "

    let $global-query := $base-query || "(" || string-join(( $groups?*?tag-q, $groups?*?cit-q , $jmmc-tags-query), ") or (") || ")"
    let $global-link := adsabs:get-query-link($global-query , "View this list on ADS in another tab", "sort=bibcode")

    let $all-new-bibcodes := if(exists($skip)) then () else try{ adsabs:search-bibcodes($global-query) } catch * { util:log("info", "error searching bibcodes for gloabl query") }
    let $all-new-bibcodes := if(empty($all-new-bibcodes) or exists($skip)) then () else try{ adsabs:search-bibcodes($global-query) } catch * { util:log("info", "error searching bibcodes for gloabl query")  }

    let $bibcodes-by-second-order :=
        map:for-each($second-order-queries, function ($tag, $q){
                let $q := '=full:('|| string-join($q ! concat('"',.,'"'), " OR ") || ')'
                let $q := $q || $global-query
                let $bibcodes := if(empty($all-new-bibcodes ) or exists($skip)) then () else adsabs:search-bibcodes($q)
                let $log := util:log("info", "We have "||count($bibcodes)||" bibcodes for second order : " || $tag)
                return
                    map:entry($tag, $bibcodes)
                })

    (: replace with last retrieved bibcodes   :)
    let $log := util:log("info","app:search-cats-analysis()/7 : found bibcodes : " || count($all-new-bibcodes))
    let $clear-candidates := if(exists($skip)) then () else adsabs:library-clear($app:LIST-OLBIN-CANDIDATES)
    let $fill-candidates := if(exists($skip)) then () else adsabs:library-add($app:LIST-OLBIN-CANDIDATES, $all-new-bibcodes)

    let $log := util:log("info","app:search-cats-analysis()/8 query each groups inside the candidates short list")
    (: Do group queries with candidates union to avoid huge gloabl search :)
    let $groups := map:merge((
        map:for-each($groups, function ($tag, $group){
            let $quickq := $group("quickq")
            let $res := if(empty($all-new-bibcodes ) or exists($skip)) then () else adsabs:search($quickq, "bibcode", false())
            let $log := util:log("info","app:search-cats-analysis()/8 ("|| count($res?response?docs?*?bibcode) || ") " || $quickq)
            return
                map:entry($tag, map:merge(( $group, map{"bibcodes":$res?response?docs?*?bibcode, "numFound":$res?response?numFound})))
            })
        ))

    (: pre-load in a single stage :)
    (: let $bibcodes := distinct-values($groups?*?bibcodes):)
    let $bibcodes:= $all-new-bibcodes
    let $records := adsabs:get-records($bibcodes)

    let $log := util:log("info","app:search-cats-analysis()/9")

    let $list-olbin-refereed-id := adsabs:library-id($app:LIST-OLBIN-REFEREED)

    let $by-bib-list := for $bibcode in $bibcodes
        let $record := adsabs:get-records($bibcode)
        order by $bibcode descending
        let $tags := for $t in map:keys($groups) return if ( $groups($t)?bibcodes[. = $bibcode] ) then $t else ()
        let $second-order-tags := map:for-each($bibcodes-by-second-order, function ($tag, $bibcodes){ if ($bibcodes=$bibcode) then $tag else () })
        let $labels := $tags ! ( <li><span class="label label-{$groups(.)?color}">{data(.)}</span></li> )
        let $second-order-labels := map:for-each($bibcodes-by-second-order, function ($tag, $bibcodes){
            if ($bibcodes=$bibcode) then <li><span class="label label-primary">{$tag}</span></li> else ()
            })
        let $olbin-add-link := "http://jmmc.fr/bibdb/addPub.php?bibcode=" || encode-for-uri($bibcode) || string-join(("", (for $t in ($tags,$second-order-tags) return "tag[]="||$t )), "&amp;")
        let $olbin-references-count := try {
                    adsabs:search-map(map{"rows":0, "q":"references("||$bibcode||") docs(library/"||$list-olbin-refereed-id||")"}, false())?response?numFound
                } catch * {
                    util:log("error","Can't get references count for "|| $bibcode),
                    -1
                }

        return
            <li>
               {adsabs:get-html($record, 3)}
                <ul class="list-inline">
                    <li><a target="_blank" href="{$olbin-add-link}">Add article to OLBIN</a>&#160;</li>
                    { $labels, $second-order-labels } ( { if($olbin-references-count=0) then <span class="label label-danger">No reference to OLBIN</span> else if($olbin-references-count<0) then <span class="label label-danger">Error getting number or references</span> else $olbin-references-count || " reference(s) part of OLBIN " } )
                </ul>
            </li>

    let $log := util:log("info","app:search-cats-analysis()/10 prepare group list")
    let $group-list := <ul class="list-inline"> {
        for $key in map:keys( $groups )
        let $value := map:get($groups,$key)
        order by $key
        return  <li>{ adsabs:get-query-link($value?q, app:badge(<span title="{$value?q}">{$key}</span>,$value("numFound"), $value("color"))) } </li>

    } </ul>

    let $log := util:log("info","app:search-cats-analysis()/11")
    return ( $refresh, $group-list, <h2>{count($by-bib-list)}/{count($bibcodes)} publications to filter and review ({$global-link})</h2>,  <ol>{$by-bib-list}</ol>, <div>Elapsed time :&#160;{jmmc-dateutil:duration($start-one, $start-two, "synchro")}&#160;{jmmc-dateutil:duration($start-two, "query")}  </div> )
};


declare function app:get-tag-table($bibcode){
    let $olbin := app:get-olbin()
    let $categories := data($olbin//category/name)
    let $e := $olbin//e[bibcode=$bibcode]
    let $e-tags := $e//tag
    return
    if(exists($e)) then
        <table class="table table-bordered">
        <tr>
            { for $category in $categories return <th>{$category}</th> }
        </tr>
        <tr>
            {
                for $category in $categories
                    let $tags := for $tag in $olbin//category[name=$category]//tag where $tag=$e-tags return (<br/>,<input  type="checkbox" checked="y">{data($tag)}</input>)
                    return <td>{subsequence($tags,2)}</td>
            }
        </tr>
        </table>
    else
        <div>No article with bibcode='{$bibcode}'</div>
};

declare function app:get-tag-table($bibcode, $e, $olbin){
    let $categories := data($olbin//category/name)
    let $e-tags := $e//tag
    return
    if(exists($e)) then
        <table class="table table-bordered">
        <tr>
            { for $category in $categories return <th>{$category}</th> }
        </tr>
        <tr>
            {
                for $category in $categories
                    let $tags := for $tag in $olbin//category[name=$category]//tag where $tag=$e-tags return (<br/>,<input  type="checkbox" checked="y">{data($tag)}</input>)
                    return <td>{subsequence($tags,2)}</td>
            }
        </tr>
        </table>
    else
        <div>No article with bibcode='{$bibcode}'</div>
};

declare function app:get-tag-consistency-map($reasons as xs:string*)  as map(*) {
    let $olbin := app:get-olbin()
    let $hidden-tags := sort( $olbin//category[name="HIDDEN"]//tag )
    let $mainCategory-tags := sort( $olbin//category[name=("MainCategory")]//tag )
    let $facility-tags := sort( $olbin//category[name=("Facility")]//tag )
    let $instrument-tags := sort( $olbin//category[name=("Instrument")]//tag )
    let $facility-or-instrument-tags := ($facility-tags,$instrument-tags)
    let $oidb-references := adsabs:library-get-bibcodes($app:LIST-JMMC-OIDB)
    let $all := empty($reasons)
    let $curated-bibcodes := adsabs:library-get-bibcodes($app:LIST-OLBIN-TAG-CURATED)
    let $entries := $olbin//e[not(bibcode=$curated-bibcodes)]

    let $li := map:merge((
        let $reason := 'Missing JMMC tag'
            return if ($all or $reason=$reasons) then
                let $bibcodes := for $e in $entries[tag=$hidden-tags] where not($e/tag[.="JMMC"]) return $e/bibcode
                return map:entry($reason,map{"label-tags": $hidden-tags,"bibcodes" : $bibcodes,"newtags": ("JMMC")}) else ()
        ,let $reason := 'Missing OiDB Data'
            return if ($all or $reason=$reasons) then
                let $bibcodes :=  for $e in $entries[tag="oidb"] where not($e/bibcode=$oidb-references) return $e/bibcode
                return map:entry($reason,map{"label-tags": $hidden-tags,"bibcodes" : $bibcodes,"newtags": ("oidb")}) else ()
        ,let $reason := 'Missing OiDB tag'
            return if ($all or $reason=$reasons) then
                let $bibcodes :=  $oidb-references[not(.=$entries//bibcode)]
                return map:entry($reason,map{"label-tags": $hidden-tags,"bibcodes" : $bibcodes,"newtags": ("oidb")}) else ()
        ,let $reason := 'Single tag'
            return if ($all or $reason=$reasons) then
            let $bibcodes := for $e in $entries where count( $e/tag) = 1 return $e/bibcode
            return map:entry($reason,map{"bibcodes" : $bibcodes}) else ()
        ,let $reason := 'No tag'
            return if ($all or $reason=$reasons) then
            let $bibcodes := for $e in $entries where not( $e/tag) return $e/bibcode
            return map:entry($reason,map{
                    "bibcodes" : $bibcodes}) else ()
        ,let $reason := 'Missing Main category tag'
            return if ($all or $reason=$reasons) then
            let $bibcodes := for $e in $entries where not( $e/tag=$mainCategory-tags) return $e/bibcode
            return map:entry($reason,map{
                    "label-tags": $mainCategory-tags,
                    "bibcodes" : $bibcodes}) else ()
        ,let $reason := 'Missing facility or instrument, when not tagged Instrumentation'
            return if ($all or $reason=$reasons) then
            let $bibcodes := for $e in $entries where not( $e/tag=($facility-or-instrument-tags,'Instrumentation')) return $e/bibcode
            return map:entry($reason,map{
                    "label-tags": $facility-or-instrument-tags,
                    "bibcodes" : $bibcodes}) else ()
        ,let $reason := 'Missing facility or instrument'
            return if ($all or $reason=$reasons) then
            let $bibcodes := for $e in $entries where not( $e/tag=($facility-or-instrument-tags)) return $e/bibcode
            return map:entry($reason,map{
                    "label-tags": $facility-or-instrument-tags,
                    "bibcodes" : $bibcodes}) else ()
        ,let $reason := 'Missing facility when instrument is present'
            return if ($all or $reason=$reasons) then
            let $bibcodes := for $e in $entries where $e/tag=$instrument-tags and not ($e/tag=($facility-tags)) return $e/bibcode
            return map:entry($reason,map{"bibcodes" : $bibcodes}) else ()
        ,let $reason := 'Missing facility, when instrument is present and not tagged Instrumentation'
            return if ($all or $reason=$reasons) then
            let $bibcodes := for $e in $entries where $e/tag=$instrument-tags and not ($e/tag=($facility-tags,'Instrumentation')) return $e/bibcode
            return map:entry($reason,map{"bibcodes" : $bibcodes}) else ()
        ,let $reason := 'Stellar parameter tag is missing but Stellar diameter is present'
            return if ($all or $reason=$reasons) then
            let $bibcodes := for $e in $entries where $e/tag="Stellar diameters" and not ($e/tag="Stellar parameters") return $e/bibcode
            return map:entry($reason,map{"bibcodes" : $bibcodes,"newtags": ("Stellar parameters")}) else ()
        ))

    let $log := util:log("info", string-join($reasons,','))
    let $log := util:log("info", $li)
    let $log := util:log("info",$all)
    let $log := util:log("info",'Facility tag is missing'=$reasons)
    let $log := util:log("info",$all or not('Facility tag is missing'=$reasons))
        let $log := util:log("info",$all or not('Stellar parameter tag is missing but Stellar diameter is present'=$reasons))

    return $li
};

declare function app:summarize-tag-consistency($node as node(), $model as map(*)) {
    let $li := app:get-tag-consistency-map(())
    return
    <div><h2>Tag curation</h2>
    <ul>
    {
          for $r in map:keys($li)
            let $map := map:get($li, $r)
            let $count := count($map?bibcodes)
            let $link := if($count>0) then
                    <a href="tag-inconsistency.html?reason={encode-for-uri($r)}">{$r}</a>
                else
                    $r
            order by count($map?bibcodes) descending
            return
                <li><b>{$link}</b> : {$count}</li>
    }
    </ul></div>
};

declare function app:fix-tag-consistency($node as node(), $model as map(*), $reason as xs:string*) {
    (: don't search all long lists :)
    if (empty($reason)) then app:summarize-tag-consistency($node, $model) else

    let $olbin := app:get-olbin()
    let $li := app:get-tag-consistency-map($reason)

    let $script := <script>
        <![CDATA[
        $( 'body' ).on( 'click', '.flagtag', function(event) {
            $.ajaxSetup({traditional: true});
            var bibcode = $(this).attr("id");
            var list = $(this).attr("data-list");
            var answer = confirm('Are you sure you want to leave proposed tags unchecked for "'+bibcode+'" paper ?');
            if (answer)
            {
                var li = $(this).parents(".pubtags");
                var tags = [];
                li.find(".candidate-tag").each(function(){tags.push($(this).text());});

                $.ajax( { url: "add-to-library.html",  data: { bibcodes: bibcode, tags: tags, list: list} } )
                .done(function() { li.remove(); })
                .fail(function() { alert( "Sorry can't process your request, please try to Sign In first" ); });
            }
        });
        ]]>
    </script>
    let $max := 200
    return
    <div>
        {
            for $r in map:keys($li)
                for $map in map:get($li, $r)
                let $bibcodes := $map?bibcodes
                    let $tags := $map?tags
                    let $newtags := $map?newtags
                    let $label-tags := $map?label-tags
                    let $li := (
                        for $bibcode in subsequence($bibcodes,1,$max)
                            let $e :=  $olbin//e[bibcode=$bibcode]
                            let $record := adsabs:get-records($bibcode)
                            order by adsabs:get-pub-date($record) descending
                            (: let $tags := if ( empty( $label-tags ) ) then $e/tag else $e/tag[.=$label-tags]
                            let $labels := $tags ! ( <li class="candidate-tag"><span class="label label-default">{data(.)}</span></li> )
                            :)
                            let $olbin-add-link := "http://jmmc.fr/bibdb/updatePubs.php?filter=" || encode-for-uri($bibcode) || string-join(("", (for $t in $newtags return "tag[]="||$t )), "&amp;")
                            return
                                <li class="pubtags ">{adsabs:get-html($record, 3)}
                                    { app:get-tag-table($bibcode) }
                                    <a class="btn btn-default" target="_blank" href="{$olbin-add-link}">✅ update OLBIN's tags</a>&#160;
                                    <button id="{$bibcode}" data-list="{$app:LIST-OLBIN-TAG-CURATED}" class="flagtag btn btn-default">🔕 Ignore / do not check anymore</button>
                                </li>
                        , (<li><b>list truncted : {count($bibcodes)} to review</b></li>)[count($bibcodes)>$max]
                    )
                    return (<div><h2>{$r} ({count($bibcodes)})</h2><ol>{$li} </ol></div>)
        }
        {$script}
    </div>
};


declare
%rest:GET
    %rest:path("/add-to-library/{$list}")
    %rest:query-param("bibcodes", "{$bibcodes}")
function app:do-add-to-library($list, $bibcodes) {
    if (jmmc-auth:isLogged()) then
        let $do := adsabs:library-add($list, $bibcodes)
        let $log := util:log("info" ,"Adding next bibcodes to " || $list  || " : " || string-join($bibcodes,","))
        return
            "Reference added"
    else
        error(xs:QName("app:error"), "Please login")

};

declare function app:add-to-library($node as node(), $model as map(*), $list as xs:string, $bibcodes as xs:string*) {
    app:do-add-to-library($list, $bibcodes)
};

declare function app:check-tags-analysis($node as node(), $model as map(*)) {

    let $log := util:log("info","app:check-tags-analysis()/1")
    let $sync-lists := try {app:sync-lists()} catch * {()}

    let $max := request:get-parameter("max", 10)

    let $jmmc-groups := $app:jmmc-doc//group[@tag and not(@tag='Others')]
    let $jmmc-groups-bibcodes := data($jmmc-groups/bibcode)

    let $log := util:log("info","app:check-tags-analysis()/2")

    let $olbin-doc := app:get-olbin()

    let $olbin-refereed-q := adsabs:library-get-search-expr($app:LIST-OLBIN-REFEREED)
    let $non-interfero-q := adsabs:library-get-search-expr($app:LIST-NON-INTERFERO)
    let $olbin-tag-reviewed-q := adsabs:library-get-search-expr($app:LIST-OLBIN-TAG-REVIEWED)
    let $blocklist-q := "( " || adsabs:library-get-search-expr($app:LIST-OLBIN-BLOCKLIST) || " OR bibstem:(" || string-join($adsabs:filtered-journals, " OR ") || ") )"

    let $log := util:log("info","app:check-tags-analysis()/5")

    let $base-query := " " || $olbin-refereed-q || " - " || $olbin-tag-reviewed-q || " "
    let $jmmc-query := " ( " || string-join( ($app:jmmc-doc/jmmc/query) , " OR " ) || " ) "

    let $groups := map:merge((
        for $group in $jmmc-groups
            let $tag := data($group/@tag)
            let $q := string-join($group/bibcode , " OR ")
            let $q := if($q) then "( citations(identifier:("||$q||")) )" else ()
            let $cit-q := if($q) then $q else ()
            let $full-q := ' full:(' || string-join(($group/@tag,$group/q) ! concat('"',lower-case(.),'"'), " OR ") ||')'
            let $q := string-join((data($q), "( " || $jmmc-query || ' AND ' || $full-q ||' )' )," OR ")
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
                    <li><button id="{$bibcode}" data-list="olbin-tag-reviewed" class="flagtag btn btn-default">Flag tag review</button> / <a class="btn btn-default" target="_blank" href="{$olbin-add-link}">update OLBIN's tags</a>&#160;</li>
                    { $labels }
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
            var list = $(this).attr("data-list");
            var answer = confirm('Are you sure you want to leave proposed tags unchecked for "'+bibcode+'" paper ?');
            if (answer)
            {
                var li = $(this).parents(".pubtags");
                var tags = [];
                li.find(".candidate-tag").each(function(){tags.push($(this).text());});

                $.ajax( { url: "add-to-library.html",  data: { bibcodes: bibcode, tags: tags, list: list} } )
                .done(function() { li.remove(); })
                .fail(function() { alert( "Sorry can't process your request, please try to Sign In first" ); });
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
    let $do-update := if( $count = $num_documents )
        then false () (: or $list-name = $app:LIST-OLBIN-REFEREED) :)
        else true()
    let $log  := util:log("info", string-join(("check-updates for",$list-name, "got", $num_documents, "vs", $count)," " ))

    return
        if ( $do-update )
        then
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
        else
            (
                util:log("info", "nothing to do !"),
                ()
            )
(:        $list-name || " uptodate" :)
};

declare function app:sync-lists(){
    app:sync-lists(false())
};

declare function app:sync-lists($force-clear){
let $clear-olbin := cache:remove($app:expirable-cache-name, "olbin-xml")

let $force-clear := if($force-clear)
    then
        (
        cache:clear($adsabs:expirable-cache-name),
        util:log("info", "Clear adsabs cache")
        )
    else ()

let $entries :=  app:get-olbin()//e
let $bibcodes := $entries//bibcode
let $fresh-libraries := adsabs:get-libraries(false())
let $existing-lib-names := data($fresh-libraries?libraries?*?name)

let $res := () (: stack results :)

let $main-updates := app:check-update($fresh-libraries, $app:LIST-OLBIN-REFEREED, $bibcodes, false())

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
    if($existing-lib-names='olbin-blocklist') then () else
    let $bbs := $app:blocklist-doc//bibcode
    (:return count($bbs):)
    return adsabs:create-library("olbin-blocklist", "Excluded papers sorted out from main Olbin list (reasons should be provided on bibdbmgr website). Helps to curate main lists.", true(), $bbs )
)

let $res := ($res,
    if($existing-lib-names=$app:LIST-OLBIN-CANDIDATES)
    then ()
    else adsabs:create-library($app:LIST-OLBIN-CANDIDATES, "Candidates (auto generated) papers sorted out from main Olbin list (reasons should be provided on bibdbmgr website). Helps to find new candidates.", true(), () )
)
let $res := ($res,
    if($existing-lib-names=$app:LIST-OLBIN-TAG-CURATED)
    then ()
    else adsabs:create-library($app:LIST-OLBIN-TAG-CURATED, "List papers which must be flagged and not be curated anymore.", true(), () )
)

let $telbibcodes := doc($app:telbib-vlti-url)//bibcode
let $res := ($res, if($existing-lib-names='telbib-vlti') then () else adsabs:create-library("telbib-vlti", "ESO telbib papers associated to VLTI instruments (automatically synchronized)", true(), () ) )
let $res := ($res , app:check-update($fresh-libraries, "telbib-vlti", $telbibcodes, false()))

let $oidb-bibcodes := jmmc-tap:tap-adql-query("http://tap.jmmc.fr/vollt/tap/sync", "SELECT DISTINCT bib_reference from oidb",())//*:TD/text()
let $res := ($res, if($existing-lib-names=$app:LIST-JMMC-OIDB) then () else adsabs:create-library($app:LIST-JMMC-OIDB,  "List of papers associated to published data in OiDB (automatically synchronized)", true(), () ) )
let $res := ($res , app:check-update($fresh-libraries, $app:LIST-JMMC-OIDB, $oidb-bibcodes, false()))


let $res := ( $res, for $tag in app:get-olbin()/publications/tag
        let $bibcodes := $entries[tag=$tag]/bibcode
        let $list-name := "tag-olbin "||$tag
        where $list-name = $existing-lib-names
        return app:check-update($fresh-libraries, $list-name, $bibcodes, false())
    )

(:  next lines could be skipped if not changes occur previously :)
let $clear-libraries := cache:remove($adsabs:expirable-cache-name, "/biblib/libraries")
let $ask-again := adsabs:get-libraries()

return <pre>{$res}</pre>
};

(:return adsabs:get-libraries()?libraries?*[?name='olbin-refereed']:)
(:for $list in $existing-lib-names:)
(:    return $list:)
(:return  count($entries//e) = $num_documents:)

declare function app:oidb-table($node as node(), $model as map(*)) {
    let $olbin := app:get-olbin()
    let $instrument-tags := $olbin//categories/category[name="Instrument"]/tag
    let $jmmc-tags := $olbin//categories/category[name="HIDDEN"]/tag

    let $bibcodes := $olbin//bibcode/text()
    let $records := adsabs:get-records($bibcodes, true()) (: global fast preshot :)
    return
    <div>
    <table class="table table-bordered table-light table-hover datatable">
        {
            for $record in subsequence($records,1,1000000)
                let $bibcode := adsabs:get-bibcode($record)
                let $title := adsabs:get-title($record)
                let $date := adsabs:get-pub-date($record)
                let $authors := string-join(adsabs:get-authors($record),";")
                let $tags := $olbin//e[bibcode=$bibcode]//tag
                let $instruments := string-join($tags[.=$instrument-tags],",")
                let $oidb := "oidb"
                let $availability := "availability"
                let $comment := "comment"
                let $class := if($tags=$jmmc-tags) then "warning" else ""
                order by $date descending, $bibcode
                return <tr><td>{adsabs:get-link($bibcode,())}</td><td class="{$class}">{$title}</td><td>{$authors}</td><td>{$date}</td><td>{$instruments}</td><td>{$oidb}</td><td>{$availability}</td><td>{$comment}</td></tr>
        }
    </table>
    </div>
};

declare function app:last-submissions($node as node(), $model as map(*), $from as xs:date?, $to as xs:date?) {
    let $olbin := app:get-olbin()
    let $instrument-tags := $olbin//categories/category[name="Instrument"]/tag
    let $jmmc-tags := $olbin//categories/category[name="HIDDEN"]/tag

    let $from := if(exists($from)) then $from else current-date()
    let $to := if(exists($to)) then $to else xs:date($from)-xs:yearMonthDuration('P3M')
    let $bibcodes := for $e in $olbin//e where xs:string($from) > $e/subdate and $e/subdate > xs:string($to)
        order by $e/subdate descending return $e/bibcode/text()

    let $records := adsabs:get-records($bibcodes) (: global fast preshot :)

    let $external-db := map{
        "oidb": adsabs:library-get-bibcodes($app:LIST-JMMC-OIDB)
        ,"jmdc": adsabs:library-get-bibcodes("jmdc-csv")
    }
    return
    <div>
    <h5>Papers submitted between <a href="?from={$from+xs:yearMonthDuration('P3M')}">&lt;&lt;</a> {$from}-{$to} <a href="?from={$to}">&gt;&gt;</a> ( {count($bibcodes)} / {count($olbin//e)} )</h5>
    <table class="table table-bordered table-light table-hover datatable">
        <thead>
            <tr>
                <th>ADS link</th><th>Title</th><th>Authors</th><th>Sub/Pub Dates</th><th>Instruments</th><th>DB</th><th>availability</th><th>Comment</th>
            </tr>
        </thead>
        {
            for $record in $records
                let $bibcode := adsabs:get-bibcode($record)
                let $title := adsabs:get-title($record)
                let $e := $olbin//e[bibcode=$bibcode]
                let $date := string-join(($e/subdate, adsabs:get-pub-date($record))," / ")
                let $authors := string-join(adsabs:get-authors($record),";")
                let $tags := $e//tag
                let $instruments := string-join($tags[.=$instrument-tags],",")
                let $tools := for $tool in map:keys($external-db) let $tools-bibcodes := $external-db($tool) where $tools-bibcodes = $bibcode return <input type="checkbox" checked="y">{data($tool)}</input>
                let $availability := "-"
                let $comment := "-"
                let $class := if($tags=$jmmc-tags) then "warning" else ""
                (: let $class := if($tags=$oidb) then "success" else $class :)
                order by $date descending, $bibcode
                return <tr><td>{adsabs:get-link($bibcode,())}</td><td class="{$class}">{$title}</td><td>{$authors}<br/>{app:get-tag-table($bibcode, $e, $olbin)}</td><td>{$date}</td><td>{$instruments}</td><td>{$tools}</td><td>{$availability}</td><td>{$comment}</td></tr>
        }
    </table>
    </div>
};

declare function app:kwic-in-abstracts($node as node(), $model as map(*), $q as xs:string?, $ads-q as xs:string?) {
    <form>
    <label>Abstract query:</label><input name="q" value="{$q}"/><br/><label>Abstract query:</label><input name="ads-q" value="{$ads-q}"/><input type="submit"/>
    </form>
    ,
    if($q != '')
    then
        let $olbin-bibcodes := app:get-olbin()//bibcode
        let $ads-query := adsabs:library-query($app:LIST-OLBIN-REFEREED)|| " " ||$ads-q
        let $records := collection("/db")//ads:record[ads:bibcode=$olbin-bibcodes]
        let $records := if ($ads-q!='') then $records[ads:bibcode=adsabs:search-bibcodes($ads-query)] else $records
        let $hits:=$records[ft:query(.//ads:abstract, $q)]
        let $bibcodes := $hits ! adsabs:get-bibcode(.)
        let $query := "bibcode:(" || string-join($bibcodes, " or ") || ")"
        return
        (
            <p>Found { adsabs:get-query-link($query, count($hits))} records over {adsabs:get-query-link($ads-query, count($records))}</p>,
            for $hit in $hits
            let $bibcode := adsabs:get-bibcode($hit)
            let $tags := for $tag in $olbin-bibcodes[.=$bibcode]/../tag return <li><span class="label label-default">{$tag}</span></li>
            order by ft:score($hit) descending
            return
                ( adsabs:get-html($hit, 3), <br/>,<ul class="list-inline">{$tags}</ul>, kwic:summarize($hit, <config width="250"/>), <br/> )
        )
    else
        ()
};
