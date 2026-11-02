{{flutter_js}}
{{flutter_build_config}}

// A GitHub Pages 404 redirect carries the original path back to the root.
const incoming = new URL(location.href);
const route = incoming.searchParams.get('__route');
const basePath = new URL(document.baseURI).pathname;
if (route && route.startsWith(basePath) && !route.startsWith('//')) {
  history.replaceState(null, '', route);
}
_flutter.loader.load({
  onEntrypointLoaded: async (initializer) => {
    const runner = await initializer.initializeEngine();
    await runner.runApp();
    document.querySelector('#startup')?.remove();
  }
});
