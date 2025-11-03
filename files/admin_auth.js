function hasValidCookie(r) {
  const c = r.headersIn['Cookie'] || '';
  return /(?:^|;\s*)ADMIN_OK=1(?:;|$)/.test(c);
}

function check(r) {
  try {
    if (hasValidCookie(r)) r.return(204);
    else r.return(401);
  } catch (e) {
    r.error(`NJS check error: ${e}`);
    r.return(500);
  }
}

function set_cookie_and_redirect(r) {
  try {
    r.headersOut['Set-Cookie'] = [
      'ADMIN_OK=1; Path=/; Max-Age=3600; HttpOnly; Secure; SameSite=Lax'
    ];
    const back = r.variables.request_uri || '/admin/';
    r.return(302, back);
  } catch (e) {
    r.error(`NJS set_cookie error: ${e}`);
    r.return(500);
  }
}

export default { check, set_cookie_and_redirect };
