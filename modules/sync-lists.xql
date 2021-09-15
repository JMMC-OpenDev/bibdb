xquery version "3.1";

import module namespace app="http://olbin.org/exist/bibdb/templates" at "app.xql";
import module namespace adsabs="http://exist.jmmc.fr/jmmc-resources/adsabs" at "/db/apps/jmmc-resources/content/adsabs.xql";
declare namespace ads="http://ads.harvard.edu/schema/abs/1.1/abstracts"; 


app:sync-lists()
