/* No dependencies. Call from a user-tapped link/button. */
(function(root) {
  function printLink(bytes, jobId, format = 'escpos') {
    if (!(bytes instanceof Uint8Array) || !bytes.length) throw Error('Provide nonempty Uint8Array print bytes');
    if (!/^[A-Za-z0-9_.-]{1,100}$/.test(jobId)) throw Error('Invalid job ID');
    if (!['escpos','tspl','raw'].includes(format)) throw Error('Invalid format');
    if (bytes.length > 20 * 1024) throw Error('Use HTTPS jobUrl for payloads over 20 KiB');
    let binary = ''; for (const b of bytes) binary += String.fromCharCode(b);
    const data = btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    const link = 'bluprintsprint://print?' + new URLSearchParams({jobId, format, data});
    if (link.length > 32768) throw Error('Link too long');
    return link;
  }
  function remoteLink(jobUrl) {
    const u = new URL(jobUrl);
    if (u.protocol !== 'https:' || u.username || u.password || u.hash) throw Error('Use HTTPS without embedded credentials or a fragment');
    const link = 'bluprintsprint://print?' + new URLSearchParams({jobUrl:u.href});
    if (link.length > 32768) throw Error('Link too long');
    return link;
  }
  root.BluprintsPrint = {printLink,remoteLink};
  if (typeof module !== 'undefined') module.exports = root.BluprintsPrint;
})(typeof window !== 'undefined' ? window : globalThis);
