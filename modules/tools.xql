xquery version "3.1";

module namespace tools="http://olbin.org/exist/bibdb/tools";

import module namespace adsabs="http://exist.jmmc.fr/jmmc-resources/adsabs" at "/db/apps/jmmc-resources/content/adsabs.xql";

declare function tools:library-as-select($library-name as xs:string, $selected-option as xs:string?, $add-none-option as xs:boolean?) {
    let $public-libs := adsabs:get-libraries()?libraries?*[?public=true()]
    return
    <select name="{$library-name}">
        {<option value="">-- none --</option>[$add-none-option]}
        {
        for $glib in $public-libs group by $prefix := tokenize($glib?name, "-")[1]
        order by $prefix ascending
        return
            <optgroup label="{$prefix}">
            {
                for $lib in $glib
                let $name := $lib?name
                order by $name
                return
                    element {"option"} { if($name=$selected-option) then attribute {"selected"} {"true"} else (), attribute {"value"} {$name}, $name||" ("||$lib?num_documents||")"}
            }
            </optgroup>
    }</select>
};

declare function tools:get-bibcodes($node as node(), $model as map(*), $library as xs:string?, $library2 as xs:string?, $user-bibcodes as xs:string?){
    let $user-bibcodes := if(data($user-bibcodes)) then
            let $bibcodes := translate($user-bibcodes, "&quot;&apos;","")
            let $bibcodes := tokenize($bibcodes, ",")
            let $bibcodes := for $b in $bibcodes return tokenize($b, ";")
            let $bibcodes := for $b in $bibcodes return tokenize($b, "&#10;")
            let $bibcodes := for $b in $bibcodes return normalize-space($b)
            let $bibcodes := reverse(sort($bibcodes[data(.)]))
            return $bibcodes
            else ()

    let $lists := map {"master list": if(exists($library)) then reverse(sort(adsabs:library-get-bibcodes($library))) else ()
        ,"user list": if(string-length($library2)>0) then reverse(sort(adsabs:library-get-bibcodes($library2))) else ()
        ,"user bibcodes" : $user-bibcodes}

    let $list1 := $lists("master list")
    let $list2 := ($lists("user list"),$lists("user bibcodes"))
    return (
    if (exists($lists) and exists($list2)) then
        <div>
            <!--<table class="table">
                    <tr>
                        <th>in both lists:</th>
                        <th>only in your <b>{$library2}</b> list</th>
                        <th>only in the <b>{$library}</b> library</th>
                    </tr>
                    <tr>
                        <td>{for $l in $list1[.=$list2] return (adsabs:get-link($l, ()), <br/>)}</td>
                        <td>{for $l in $list2[not(.=$list1)] return (adsabs:get-link($l, ()), <br/>)}</td>
                        <td>{for $l in $list1[not(.=$list2)] return (adsabs:get-link($l, ()), <br/>)}</td>
                    </tr>
            </table>-->
            <table class="table">
                    <tr>
                        <th><b>{$library}</b> library</th>
                        <th><b>{$library2}</b> list</th>
                    </tr>
                    {
                        for $bibcodes in ($list1, $list2) group by $bibcode:=$bibcodes
                        order by $bibcode
                        let $class := if($bibcode=$list1 and $bibcode=$list2) then "success" else "danger"
                        return
                        <tr class="{$class}">
                        <td>{if($bibcode = $list1) then adsabs:get-link($bibcode, ()) else ()}</td>
                        <td>{if($bibcode = $list2) then adsabs:get-link($bibcode, ()) else ()}</td>
                    </tr>
                    }
            </table>
        </div>
    else ()
    ,
    for $list in map:keys($lists)
        return if (exists($lists($list))) then
    <div>
        {
            let $bibcodes := $lists($list)
            return
            <div>
                <h5>Bibcodes of '{$list}' list</h5>
                <pre>
                {string-join($bibcodes, "&#10;")}
                </pre>
            </div>
        }
    </div>
    else (),
    if( empty($library) or true() ) then
        <div>
            Choose the master library you want to compare bibcodes with:
            <form>
                {tools:library-as-select("library", $library, false())}
                <input type="submit"/>
                <br/>
                Optional bibcodes list to check against master library:
                <textarea class="form-control" rows="5" name="user-bibcodes">{string-join($user-bibcodes, "&#10;")}</textarea>
                Optional library to check against master library:
                {tools:library-as-select("library2", $library2,true())}
            </form>
        </div>
    else ()
    )
};