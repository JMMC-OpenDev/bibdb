xquery version "3.0";

import module namespace login="http://exist-db.org/xquery/login" at "resource:org/exist/xquery/modules/persistentlogin/login.xql";

declare variable $exist:path external;
declare variable $exist:resource external;
declare variable $exist:controller external;
declare variable $exist:prefix external;
declare variable $exist:root external;


declare variable $domain := "fr.jmmc.oidb.login";
declare variable $login-max-age := xs:dayTimeDuration("P7D");
(: call login function before any use of protected code         :)
(: app:user-admin() and app:user-allowed() uses this attributes :)
(: moving to 5.2 requires an additional call in our restxq module :)

(: TODO check if we can move/hide it in app module :) 
declare variable $login := function () {
    login:set-user($domain, $login-max-age, false())
(:    ,util:log("info", "1 logged as "|| serialize(sm:id())):)
(:    ,util:log("info", "2 logged as "|| request:get-attribute($domain || '.user')):)
};




if ($exist:path eq '') then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="{request:get-uri()}/"/>
    </dispatch>
    
else if ($exist:path eq "/") then
    (: forward root path to index.xql :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="index.html"/>
    </dispatch>
    
else if (ends-with($exist:resource, ".html")) then
    let $login := $login()
    return 
    (: the html page is run through view.xql to expand templates :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <view>
            <forward url="{$exist:controller}/modules/view.xql">
                <set-header name="Cache-Control" value="no-cache, no-store, must-revalidate"/>
                <set-header name="Pragma" value="no-cache"/>
                <set-header name="Expires" value="0"/>
            </forward>
        </view>
		<error-handler>
			<forward url="{$exist:controller}/error-page.html" method="get"/>
			<forward url="{$exist:controller}/modules/view.xql"/>
		</error-handler>
    </dispatch>
(: Resource paths starting with $shared are loaded from the shared-resources app :)
else if (contains($exist:path, "/$shared/")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="/shared-resources/{substring-after($exist:path, '/$shared/')}">
            <set-header name="Cache-Control" value="max-age=3600, must-revalidate"/>
        </forward>
    </dispatch>
else
    (: everything else is passed through :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <cache-control cache="yes"/>
    </dispatch>
