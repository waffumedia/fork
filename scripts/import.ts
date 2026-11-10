/** npm run import  — load every data/sources/*.json into the database. */
import { importAll } from "../lib/library";
importAll().then((r) => { console.log(JSON.stringify(r, null, 2)); process.exit(r.errors.length ? 1 : 0); });
