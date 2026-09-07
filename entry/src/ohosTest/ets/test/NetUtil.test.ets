import { describe, it, expect } from '@ohos/hypium';
import { UrlUtil } from '../../../main/ets/utils/net/UrlUtil';
import { CookieContainer } from '../../../main/ets/service/network/CookieContainer';

export default function netUtilTest() {
  describe('netUtilTest', () => {
    it('formEncode', 0, () => {
      const fields: Map<string, string> = new Map();
      fields.set('a', '1&2');
      fields.set('b', '中文');
      fields.set('c', 'plain');
      const encoded: string = UrlUtil.formEncode(fields);
      expect(encoded).assertContain('a=1%262');
      expect(encoded).assertContain('c=plain');
      expect(encoded).assertContain('%E4%B8%AD%E6%96%87');
    });

    it('resolveRedirectVariants', 0, () => {
      expect(UrlUtil.resolveRedirect('https://a.b/c/d', '/e?f')).assertEqual('https://a.b/e?f');
      expect(UrlUtil.resolveRedirect('https://a.b/c/d', 'g')).assertEqual('https://a.b/c/g');
      expect(UrlUtil.resolveRedirect('https://a.b/c/d', '//x.y/z')).assertEqual('https://x.y/z');
      expect(UrlUtil.resolveRedirect('https://a.b/c/d', 'https://q.r/s')).assertEqual('https://q.r/s');
      expect(UrlUtil.resolveRedirect('https://a.b/c/d', '')).assertEqual('https://a.b/c/d');
    });

    it('hostAndPath', 0, () => {
      expect(UrlUtil.hostOf('https://IDs.Xidian.edu.cn/authserver/login')).assertEqual('ids.xidian.edu.cn');
      expect(UrlUtil.pathOf('https://ids.xidian.edu.cn/authserver/login?service=x')).assertEqual('/authserver/login');
      expect(UrlUtil.pathOf('https://ids.xidian.edu.cn')).assertEqual('/');
    });

    it('cookieDomainMatch', 0, () => {
      const jar: CookieContainer = new CookieContainer();
      const requestUrl: string = 'https://ids.xidian.edu.cn/authserver/login';
      jar.setFromSetCookieStrings(['CASTGC=TGT-abc; Domain=.xidian.edu.cn; Path=/'], requestUrl);
      expect(jar.cookieHeader('https://ehall.xidian.edu.cn/jwapp/sys/wdkb')).assertEqual('CASTGC=TGT-abc');
      expect(jar.cookieHeader('https://evil.example.com/')).assertEqual('');
    });

    it('cookieHostOnlyAndPath', 0, () => {
      const jar: CookieContainer = new CookieContainer();
      jar.setFromSetCookieStrings(['SID=xyz; Path=/app'], 'https://host.example.com/app/page');
      expect(jar.cookieHeader('https://host.example.com/app/other')).assertEqual('SID=xyz');
      expect(jar.cookieHeader('https://host.example.com/other')).assertEqual('');
      expect(jar.cookieHeader('https://other.example.com/app/other')).assertEqual('');
    });

    it('cookieReplaceAndSerialize', 0, () => {
      const jar: CookieContainer = new CookieContainer();
      jar.setFromSetCookieStrings(['K=v1'], 'https://h.example.com/a');
      jar.setFromSetCookieStrings(['K=v2'], 'https://h.example.com/b');
      expect(jar.allCookies().length).assertEqual(1);
      expect(jar.cookieHeader('https://h.example.com/c')).assertEqual('K=v2');
      const snapshot: string = jar.serialize();
      const restored: CookieContainer = new CookieContainer();
      restored.loadFrom(snapshot);
      expect(restored.cookieHeader('https://h.example.com/c')).assertEqual('K=v2');
      restored.clear();
      expect(restored.isEmpty()).assertTrue();
    });
  });
}
