import { describe, it, expect } from '@ohos/hypium';
import { HtmlParser, HtmlNode } from '../../../main/ets/utils/html/HtmlParser';

const SAMPLE: string = '<!DOCTYPE html><html><head><title>测试</title></head><body>' +
  '<form id="f" action="/authserver/login" method="post">' +
  '<input type="text" name="username" value="stu123">' +
  '<input type="hidden" name="lt" value="LT-123456">' +
  '<input type="hidden" name="execution" value="e1s2">' +
  '<input type="password" name="password">' +
  '</form>' +
  '<span id="showErrorTip" class="error tip">用户名或密码有误</span>' +
  '<div class="a b" data-x="1&amp;2"><p>段落一</p> <p>段落二</p></div>' +
  '<img src="captcha.png"><span id="after">after</span>' +
  '</body></html>';

export default function htmlParserTest() {
  describe('htmlParserTest', () => {
    it('hiddenInputExtraction', 0, () => {
      const root: HtmlNode = HtmlParser.parse(SAMPLE);
      const lt: HtmlNode[] = HtmlParser.querySelectorAll(root, '#f input[name=lt]');
      expect(lt.length).assertEqual(1);
      expect(lt[0].attr('value')).assertEqual('LT-123456');
      const execution: HtmlNode[] = HtmlParser.querySelectorAll(root, 'input[name="execution"]');
      expect(execution.length).assertEqual(1);
      expect(execution[0].attr('value')).assertEqual('e1s2');
    });

    it('errorTipText', 0, () => {
      const root: HtmlNode = HtmlParser.parse(SAMPLE);
      const tip: HtmlNode | null = HtmlParser.getElementById(root, 'showErrorTip');
      expect(tip !== null).assertTrue();
      if (tip !== null) {
        expect(tip.normalizedText()).assertEqual('用户名或密码有误');
        expect(tip.classNames().length).assertEqual(2);
      }
    });

    it('voidElementDoesNotSwallowSiblings', 0, () => {
      const root: HtmlNode = HtmlParser.parse(SAMPLE);
      const imgs: HtmlNode[] = HtmlParser.getElementsByTagName(root, 'img');
      expect(imgs.length).assertEqual(1);
      expect(imgs[0].children.length).assertEqual(0);
      const after: HtmlNode | null = HtmlParser.getElementById(root, 'after');
      expect(after !== null).assertTrue();
      if (after !== null) {
        expect(after.parent !== null).assertTrue();
        if (after.parent !== null) {
          expect(after.parent.tag).assertEqual('body');
        }
      }
    });

    it('tagAndClassQueries', 0, () => {
      const root: HtmlNode = HtmlParser.parse(SAMPLE);
      expect(HtmlParser.getElementsByTagName(root, 'input').length).assertEqual(4);
      const div: HtmlNode[] = HtmlParser.getElementsByClassName(root, 'a');
      expect(div.length).assertEqual(1);
      expect(HtmlParser.getElementsByClassName(root, 'b').length).assertEqual(1);
      expect(div[0].attr('data-x')).assertEqual('1&2');
    });

    it('titleRawTextAndTextContent', 0, () => {
      const root: HtmlNode = HtmlParser.parse(SAMPLE);
      const title: HtmlNode[] = HtmlParser.getElementsByTagName(root, 'title');
      expect(title.length).assertEqual(1);
      expect(title[0].textContent()).assertEqual('测试');
      const body: HtmlNode[] = HtmlParser.getElementsByTagName(root, 'body');
      expect(body[0].textContent()).assertContain('段落一');
      expect(body[0].textContent()).assertContain('段落二');
    });

    it('entityDecoding', 0, () => {
      expect(HtmlParser.decodeEntities('&lt;a&gt;&amp;')).assertEqual('<a>&');
      expect(HtmlParser.decodeEntities('&#x4E2D;&#25991;')).assertEqual('中文');
      expect(HtmlParser.decodeEntities('&nbsp;')).assertEqual(' ');
      expect(HtmlParser.decodeEntities('plain&unknown')).assertEqual('plain&unknown');
    });

    it('descendantCombinator', 0, () => {
      const root: HtmlNode = HtmlParser.parse(SAMPLE);
      expect(HtmlParser.querySelectorAll(root, 'form input[type=hidden]').length).assertEqual(2);
      expect(HtmlParser.querySelectorAll(root, 'div p').length).assertEqual(2);
      expect(HtmlParser.querySelectorAll(root, 'p input').length).assertEqual(0);
    });
  });
}
