export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname.startsWith("/downloads/")) {
      const key = url.pathname.slice("/downloads/".length);

      if (!key || key.includes("..")) {
        return new Response("Not found", { status: 404 });
      }

      const object = await env.APK_BUCKET.get(key);
      if (!object) {
        return new Response("APK not found", { status: 404 });
      }

      const headers = new Headers();
      object.writeHttpMetadata(headers);
      headers.set("etag", object.httpEtag);
      headers.set("content-type", "application/vnd.android.package-archive");
      headers.set("content-length", String(object.size));
      headers.set("cache-control", key.endsWith("-latest.apk")
        ? "public, max-age=300"
        : "public, max-age=31536000, immutable");

      if (request.method === "HEAD") {
        return new Response(null, { status: 200, headers });
      }

      return new Response(object.body, { status: 200, headers });
    }

    return env.ASSETS.fetch(request);
  },
};
