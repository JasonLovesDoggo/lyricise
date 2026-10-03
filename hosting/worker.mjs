const repository = 'https://github.com/JasonLovesDoggo/lyricise';

export default {
  fetch(request) {
    if (!['GET', 'HEAD'].includes(request.method)) {
      return new Response('Method not allowed', { status: 405, headers: { Allow: 'GET, HEAD' } });
    }
    const path = new URL(request.url).pathname;
    if (path === '/install.sh') {
      return Response.redirect(`${repository}/releases/latest/download/install.sh`, 302);
    }
    if (path === '/') return Response.redirect(repository, 302);
    return new Response('Not found', { status: 404 });
  },
};
