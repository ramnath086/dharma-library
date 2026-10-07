export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname.startsWith("/downloads/")) {
      const key = url.pathname.slice("/downloads/".length);

      if (!key || key.includes("..") || !/^(dharma-library-(latest|v[0-9]+\.[0-9]+\.[0-9]+)\.apk)$/.test(key)) {
        return new Response("Not found", { status: 404 });
      }

      const object = await env.APK_BUCKET.get(key, {
        range: request.headers,
        onlyIf: request.headers,
      });

      if (!object) {
        return new Response("APK not found", { status: 404 });
      }

      const headers = new Headers();
      object.writeHttpMetadata(headers);
      headers.set("etag", object.httpEtag);
      headers.set("content-type", "application/vnd.android.package-archive");
      headers.set("content-disposition", `attachment; filename="${key}"`);

      if ("body" in object && object.body) {
        if (object.range) {
          const start = object.range.offset ?? 0;
          const length = object.range.length ?? object.size;
          headers.set("content-length", String(length));
          headers.set("content-range", `bytes ${start}-${start + length - 1}/${object.size}`);
          return new Response(object.body, { status: 206, headers });
        }

        headers.set("content-length", String(object.size));
        return new Response(object.body, { status: 200, headers });
      }

      return new Response(null, { status: 412, headers });
    }

    return env.ASSETS.fetch(request);
  },
};
