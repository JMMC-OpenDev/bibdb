xquery version "3.1";

import module namespace app="http://olbin.org/exist/bibdb/templates" at "/db/apps/bibdb/modules/app.xql";
import module namespace adsabs="http://exist.jmmc.fr/jmmc-resources/adsabs" at "/db/apps/jmmc-resources/content/adsabs.xql";
declare namespace ads="https://ads.harvard.edu/schema/abs/1.1/abstracts"; 


let $bibdb-entries :=  app:get-olbin()//e
let $bibdb-entries :=  subsequence(app:get-olbin()//e,5,10)
(: prefetch every records in a single call :)
let $cache-records := adsabs:get-records($bibdb-entries//bibcode)
let $astro-topic := app:get-olbin()//category[name="Astrophysical topic"]//tag

let $html := <html>
        <h1>Liste comparative des tags OLBIN (Astrophysical topic en gras) vs. Keywords ADS</h1>
        
        <h2>Tous tags confondus</h2>
        <table border="1">
            <tr>
                <td><ul>
                    {
                        for $tag in data($bibdb-entries//tag) group by $l:=$tag order by $l
                        return <li>{ if ($l=$astro-topic) then <b>{$l}</b> else $l }</li>
                    }
                </ul></td>
                <td><ul>
                    {
                        for $kw in data($cache-records//ads:keyword) group by $l:=$kw order by $l
                        return <li><b>{$l}</b></li>
                    }
                </ul></td>
            </tr>        
        </table>
        <h2>Par publication</h2>
        <table border="1">
        {
            for $bibdb-entrie at $pos in $bibdb-entries
            let $bibcode:=$bibdb-entrie//bibcode
            let $record:=adsabs:get-records($bibcode)
            return 
                
                        <tr>
                            <td>{$pos}/<br/>{adsabs:get-html($record, 3)}</td>
                            <td><ul>
                                {
                                    for $l in data($bibdb-entrie//tag) order by $l
                                    return <li>{ if ($l=$astro-topic) then <b>{$l}</b> else $l }</li>
                                }
                            </ul></td>
                            <td><ul>
                                {
                                    for $l in data($record//ads:keyword) order by $l
                                    return <li><b>{$l}</b></li>
                                }
                            </ul></td>
                        </tr>        
        }
        </table>
    </html>

return 
    try{
      xmldb:store("/db/apps/bibdb", "tmp.html", $html)
    }catch*{
    response:set-header("Content-Type","text/html"), 
    $html
    }
