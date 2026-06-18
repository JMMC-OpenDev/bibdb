xquery version "3.1";

module namespace comments="http://olbin.org/exist/bibdb/comments";
import module namespace config="http://olbin.org/exist/bibdb/config" at "config.xqm";
import module namespace jmmc-auth="http://exist.jmmc.fr/jmmc-resources/auth";
import module namespace adsabs="http://exist.jmmc.fr/jmmc-resources/adsabs" at "/db/apps/jmmc-resources/content/adsabs.xql";


declare %private variable $comments:comments-doc-path := $config:data-root||"/comments.xml";
declare variable $comments:comments-doc := doc($comments:comments-doc-path)/*;
declare variable $comments:level-map := map{"info":"info","debug":"info","warning":"warn","error":"error"};


declare function comments:button($bibcode){
  let $comments :=comments:get-comments($bibcode)
  let $button := if( exists($comments) )
  then
    <a class="btn btn-primary" href="comments.html?bibcode={encode-for-uri($bibcode)}" target="_blank">
        <span class="badge">{count($comments)}</span> View comments <span class="glyphicon glyphicon-search" aria-hidden="true"></span>
    </a>
  else
    <a class="btn btn-default" href="comments.html?bibcode={encode-for-uri($bibcode)}" target="_blank">
        Add comment <span class="glyphicon glyphicon-plus" aria-hidden="true"></span>
    </a>
    return
        $button
};

declare function comments:get-comments(){
    $comments:comments-doc/comment
};

declare function comments:get-comments($bibcode){
    $comments:comments-doc/comment[bibcode=$bibcode]
};

declare function comments:add-comment($bibcode, $msg){
    (: do not use current-dateTime because value may be the same in loop's calls :)
    (
    util:log("info", "add new comment for "||$bibcode),
    update insert <comment>
        <by>{jmmc-auth:get-obfuscated-email(session:get-attribute("email"))}</by>
        <bibcode>{$bibcode}</bibcode>
        <msg>{$msg}</msg>
        <date>{util:system-dateTime()}</date>
        </comment> into $comments:comments-doc
    )
};
declare function comments:display($node as node(), $model as map(*), $bibcode as xs:string*, $new-comment as xs:string*) {
    if(jmmc-auth:is-logged()) then
        comments:do_display($node, $model, $bibcode, $new-comment)
    else
        (
            (: leave a comment link to help the user to go back on this page :)
            session:set-attribute('next-link', <a href="comments.html?bibcode={encode-for-uri($bibcode)}">Go to the comment page for {$bibcode}</a>),
            <span><b>Please <a href="login.html">login</a> to access comments.</b></span>
        )
};


declare function comments:do_display($node as node(), $model as map(*), $bibcode as xs:string?, $new-comment as xs:string?) {
    let $single :=  string-length($bibcode)>6
    let $form := if (string-length($bibcode)>6 ) then
        <form method="get">
            <textarea class="form-control" rows="3" name="new-comment"></textarea>
            <input type="hidden" name="bibcode" value="{$bibcode}"/>
            <button type="submit" class="btn btn-default" value="submit">Add new comment</button>
        </form>
        else
            ()

    let $do := if(string-length($new-comment) * string-length($bibcode) > 1) then
            comments:add-comment($bibcode, $new-comment)
        else
            ()

    let $comments := reverse(if(string-length($bibcode)>0) then comments:get-comments()[matches(bibcode,$bibcode,"i")] else comments:get-comments())
    return
    <div>
    {$do}
    {if ($single) then
        (<h1>Bibcode : {$bibcode}</h1>,
         <div>{adsabs:get-html(adsabs:get-records($bibcode), 100)}</div>) else ()}
    <table class="table table-bordered table-condensed">
        <thead><tr>{if ($single) then () else <th>Bibcode</th>}<th>&#160;Comments (total {count($comments)})</th></tr></thead>
        <tbody>{
        for $gcomment in $comments group by $bib := $gcomment/bibcode
        return <tr>
            {if ($single) then () else <td>{data($bib)}</td>}
            <td>
            { for $comment in $gcomment
                return
                    <div><b>{data($comment/by)}</b> on {data($comment/date)}<br/> <pre>{data($comment/msg)}</pre></div>
            }
            </td>
            </tr>
        }</tbody>
    </table>

    <br/>
    {$form}
    </div>
};
