xquery version "3.1";

module namespace app="http://olbin.org/exist/bibdb/templates";

import module namespace templates="http://exist-db.org/xquery/templates" ;
import module namespace config="http://olbin.org/exist/bibdb/config" at "config.xqm";
import module namespace adsabs="http://exist.jmmc.fr/jmmc-resources/adsabs" at "/db/apps/jmmc-resources/content/adsabs.xql";
import module namespace jmmc-auth="http://exist.jmmc.fr/jmmc-resources/auth";

(:declare variable $app:olbin-doc := doc($config:data-root||"/olbin.xml"); replace by app:get-olbin:)
declare variable $app:jmmc-doc := doc($config:data-root||"/jmmc.xml");
declare variable $app:blacklist-doc := doc($config:data-root||"/blacklists.xml");


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
        ,[("Which impact of OLBIN outside its own field ?" , "property:refereed citations("||$l||") - "||$l)]
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
                () (: We are uptodate :)
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
    ("CHARA", "COAST", "GI2T", "I2T", "IACT", "IOTA", "IRMA", "ISI", "Keck", "LBTI", "Mark III", "NPOI", "Narrabri Stellar Intensity Interferometer", "PTI", "SIM", "SUSI", "VLTI")
};
declare function app:jmmc-non-interfero($node as node(), $model as map(*)){
   <div>
        <h2>Helpers to catch OLBIN papers ( pour Alain! )</h2>
        <ol>{
        let $olbin-refereed-q := adsabs:library-get-search-expr($app:LIST-OLBIN-REFEREED)
        let $non-interfero-q := adsabs:library-get-search-expr($app:LIST-NON-INTERFERO)
        let $blacklist-q := "( " || adsabs:library-get-search-expr($app:LIST-OLBIN-BLACKLIST) || " OR bibstem:(" || string-join($adsabs:filtered-journals, " OR ") || ") )"
        
        let $interferometers :=  ( app:get-interferometers() ! concat('"',.,'"') => string-join(" or ") ) ! concat('(',.,')')
        
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
        let $big-q := "property:refereed full:" || $interferometers
        let $big-query := adsabs:get-query-link($big-q,<b data-trigger="hover" data-toggle="popover" data-original-title="{$big-q}" data-content="">Interferometer names in full text</b>)
        let $big-q := $big-q ||" - abs:(VLTI or CHARA or LBTI)"
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
let $jmmc-groups := $app:jmmc-doc//group[@tag and not(@tag='Others')]
    let $jmmc-groups-bibcodes := data($jmmc-groups/bibcode)
    
    let $olbin-doc := app:get-olbin()
    let $olbin-bibcodes := data($olbin-doc//bibcode) (: could be ads list ? :)
    let $non-interfero-bibcodes := data(adsabs:library-get-bibcodes($app:LIST-NON-INTERFERO))
    let $blacklist-bibcodes := data(adsabs:library-get-bibcodes($app:LIST-OLBIN-BLACKLIST))
    let $jmmc-papers-bibcodes := data(adsabs:library-get-bibcodes($app:LIST-JMMC-PAPERS))
    
    let $olbin-refereed-q := adsabs:library-get-search-expr($app:LIST-OLBIN-REFEREED)
    let $non-interfero-q := adsabs:library-get-search-expr($app:LIST-NON-INTERFERO)
    let $blacklist-q := "( " || adsabs:library-get-search-expr($app:LIST-OLBIN-BLACKLIST) || " OR bibstem:(" || string-join($adsabs:filtered-journals, " OR ") || ") )"

    let $missing-jmmc-papers-bibcodes := $jmmc-groups-bibcodes[not(.=$jmmc-papers-bibcodes)]
    let $missing-jmmc-papers := if(exists($missing-jmmc-papers-bibcodes)) then "identifier:("|| string-join($missing-jmmc-papers-bibcodes, ' or ')||")" else ()
    let $missing-jmmc-papers := if($missing-jmmc-papers) then adsabs:get-query-link($missing-jmmc-papers,"Please add next jmmc-papers in ADS or move out xmldb") else ()


    let $missing-in-groups := for $record in adsabs:get-records($jmmc-papers-bibcodes[not(.=$jmmc-groups-bibcodes)]) return <li>&lt;!--{adsabs:get-title($record)}--&gt;<br/>{ serialize(<bibcode>{adsabs:get-bibcode($record)}</bibcode>)} </li>
    let $missing-in-groups := if($missing-in-groups) then <div><h4>ADS jmmc-papers not present in local db</h4><ul> {$missing-in-groups}</ul></div> else ()
    
    let $base-query := " property:refereed - " || $olbin-refereed-q || " - " || $blacklist-q ||" - " || $non-interfero-q || " "
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
        for $tag  in ("VLTI", "CHARA", "LBTI")
            let $q := "full:'"|| $tag || "'"
            let $sub-q := $q
            let $q := $q || $base-query
            let $res := adsabs:search($q, "bibcode")
            return
                map:entry($tag, map{"q":$q , "tag-q":$sub-q, "bibcodes":$res?response?docs?*?bibcode, "numFound":$res?response?numFound, "color":"success" })
        ))
    
    let $group-list := <ul class="list-inline"> {map:for-each( $groups, function ($key, $value) { <li>
        { adsabs:get-query-link($value?q, app:badge(<span title="{$value?q}">{$key}</span>,$value("numFound"), $value("color"))) } </li> } ) } </ul>
    
    (: pre-load in a single stage :)
    let $bibcodes := distinct-values($groups?*?bibcodes)
    let $records := adsabs:get-records($bibcodes)
    
    let $by-bib-list := for $bibcode in $bibcodes order by $bibcode descending
        let $record := adsabs:get-records($bibcode)
        return 
            <li>{adsabs:get-html($record, 3)}
                <ul>
                    { 
                        for $t in map:keys($groups) 
                        return 
                            if ( $groups($t)?bibcodes[. = $bibcode] ) then ("&#160;", <span class="label label-{$groups($t)?color}">{data($t)}</span>) else ()
                    }
                </ul>
            </li>
    let $jmmc-tags-query := $jmmc-query || " and ( " || 
        string-join( ( ($groups?*?full-q) ! concat( '(', ., ')' ) ) , " or ")
        || " ) "
    
    let $global-query := $base-query || string-join(( $groups?*?tag-q, $groups?*?cit-q , $jmmc-tags-query), " or ")
    let $global-link := adsabs:get-query-link($global-query , "View this list on ADS")
    return ( $group-list, <h2>{count($by-bib-list)} publications to filter and review ({$global-link})</h2>,  <ol>{$by-bib-list}</ol> )
};
