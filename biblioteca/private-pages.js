// Flipbook transport: no public or signed URLs, no original PDF.
export function privatePages(db) {
  let epoch = 0;
  const urls = new Set();
  function release(url) {
    if (urls.delete(url)) URL.revokeObjectURL(url);
  }
  function clear() {
    epoch++;
    for (const url of urls) URL.revokeObjectURL(url);
    urls.clear();
  }
  function validBook(id) {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) throw Error('Invalid book');
  }
  async function manifest(id) {
    validBook(id);
    const g = epoch;
    const {data,error} = await db.rpc('gmv_page_manifest',{p_book:id});
    if (g !== epoch) throw Error('Reader closed');
    if (error || !Array.isArray(data) || !data.length) throw Error('Publication unavailable');
    if (data.some((p,i)=>p.ordinal!==i+1 || !Number.isInteger(p.width_px) || !Number.isInteger(p.height_px) || p.width_px<=0 || p.height_px<=0)) throw Error('Invalid page manifest');
    return data;
  }
  async function page(id, ordinal) {
    validBook(id);
    if (!Number.isSafeInteger(ordinal) || ordinal<1) throw Error('Invalid page');
    const g = epoch;
    const {data,error} = await db.storage.from('gmv-private-pages').download(id+'/'+ordinal+'.webp');
    if (g !== epoch) throw Error('Reader closed');
    if (error || !(data instanceof Blob) || !data.size) throw Error('Page unavailable');
    const header = new Uint8Array(await data.slice(0,12).arrayBuffer());
    if (g !== epoch) throw Error('Reader closed');
    if (String.fromCharCode(...header.slice(0,4))!=='RIFF' || String.fromCharCode(...header.slice(8,12))!=='WEBP') throw Error('Invalid page format');
    const url = URL.createObjectURL(new Blob([data],{type:'image/webp'}));
    urls.add(url);
    return url;
  }
  return {manifest,page,release,clear};
}
