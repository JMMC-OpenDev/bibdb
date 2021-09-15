xquery version "3.1";

import module namespace json="http://www.json.org";
import module namespace app="http://olbin.org/exist/bibdb/templates" at "modules/app.xql";

declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "json";
declare option output:media-type "application/json";


parse-json( json:xml-to-json( app:get-olbin()//categories) ) 
