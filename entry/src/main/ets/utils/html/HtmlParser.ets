import { Log } from '../Log';

/**
 * 轻量 HTML DOM 解析器（自研子集，替代 Dart html 包）。
 *
 * 覆盖能力：标签/属性/文本树构建、void 元素、script/style 原文、注释与 DOCTYPE 跳过、
 * 基本实体解码、getElementById / getElementsByTagName / getElementsByClassName、
 * querySelectorAll 子集（tag / #id / .class / [attr=v] 组合 + 后代空格组合器 + 逗号分组）。
 * 已知取舍：不实现浏览器式隐式闭合（如 <p> 自动闭合），校方页面查询按标签名/ID/类名足够。
 */
export class HtmlNode {
  static readonly DOCUMENT: string = '#document';
  static readonly TEXT: string = '#text';

  tag: string = HtmlNode.DOCUMENT;
  isText: boolean = false;
  text: string = '';
  attributes: Map<string, string> = new Map();
  children: HtmlNode[] = [];
  parent: HtmlNode | null = null;

  id(): string {
    const v: string | undefined = this.attributes.get('id');
    return v !== undefined ? v : '';
  }

  attr(name: string): string {
    const v: string | undefined = this.attributes.get(name);
    return v !== undefined ? v : '';
  }

  hasAttr(name: string): boolean {
    return this.attributes.has(name);
  }

  classNames(): string[] {
    const raw: string = this.attr('class');
    if (raw.length === 0) {
      return [];
    }
    return raw.split(/\s+/).filter((s: string): boolean => s.length > 0);
  }

  isElement(): boolean {
    return !this.isText && this.tag !== HtmlNode.DOCUMENT;
  }

  textContent(): string {
    let out: string = '';
    for (let i = 0; i < this.children.length; i++) {
      const child: HtmlNode = this.children[i];
      if (child.isText) {
        out += child.text;
      } else {
        out += child.textContent();
      }
    }
    return out;
  }

  ownText(): string {
    let out: string = '';
    for (let i = 0; i < this.children.length; i++) {
      const child: HtmlNode = this.children[i];
      if (child.isText) {
        out += child.text;
      }
    }
    return out.trim();
  }

  normalizedText(): string {
    return HtmlNode.collapseWhitespace(this.textContent()).trim();
  }

  static collapseWhitespace(input: string): string {
    return input.replace(/\s+/g, ' ');
  }
}

class SimpleSelector {
  tag: string = '';
  id: string = '';
  classes: string[] = [];
  attrName: string = '';
  attrValue: string = '';
  attrMustMatchValue: boolean = false;

  matches(node: HtmlNode): boolean {
    if (!node.isElement()) {
      return false;
    }
    if (this.tag.length > 0 && this.tag !== '*' && node.tag !== this.tag) {
      return false;
    }
    if (this.id.length > 0 && node.id() !== this.id) {
      return false;
    }
    const nodeClasses: string[] = node.classNames();
    for (let i = 0; i < this.classes.length; i++) {
      let found: boolean = false;
      for (let j = 0; j < nodeClasses.length; j++) {
        if (nodeClasses[j] === this.classes[i]) {
          found = true;
          break;
        }
      }
      if (!found) {
        return false;
      }
    }
    if (this.attrName.length > 0) {
      if (!node.hasAttr(this.attrName)) {
        return false;
      }
      if (this.attrMustMatchValue && node.attr(this.attrName) !== this.attrValue) {
        return false;
      }
    }
    return true;
  }
}

export class HtmlParser {
  private static readonly VOID_TAGS: Set<string> = new Set<string>([
    'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link',
    'meta', 'param', 'source', 'track', 'wbr'
  ]);
  private static readonly RAW_TEXT_TAGS: Set<string> = new Set<string>([
    'script', 'style', 'textarea', 'title'
  ]);

  static parse(html: string): HtmlNode {
    const root: HtmlNode = new HtmlNode();
    const stack: HtmlNode[] = [root];
    let i: number = 0;
    const len: number = html.length;
    while (i < len) {
      const ltIndex: number = html.indexOf('<', i);
      if (ltIndex < 0) {
        HtmlParser.appendTextTo(stack[stack.length - 1], html.substring(i));
        break;
      }
      if (ltIndex > i) {
        HtmlParser.appendTextTo(stack[stack.length - 1], html.substring(i, ltIndex));
      }
      if (html.startsWith('<!--', ltIndex)) {
        const commentEnd: number = html.indexOf('-->', ltIndex + 4);
        i = commentEnd < 0 ? len : commentEnd + 3;
        continue;
      }
      if (html.startsWith('<!', ltIndex) || html.startsWith('<?', ltIndex)) {
        const declEnd: number = html.indexOf('>', ltIndex);
        i = declEnd < 0 ? len : declEnd + 1;
        continue;
      }
      if (html.startsWith('</', ltIndex)) {
        const closeEnd: number = html.indexOf('>', ltIndex);
        if (closeEnd < 0) {
          i = len;
          break;
        }
        const closeTag: string = html.substring(ltIndex + 2, closeEnd).trim().toLowerCase();
        HtmlParser.handleCloseTag(stack, closeTag);
        i = closeEnd + 1;
        continue;
      }
      const parseResult: TagParseResult = HtmlParser.parseTag(html, ltIndex);
      if (parseResult.nextIndex < 0) {
        i = len;
        break;
      }
      i = parseResult.nextIndex;
      if (parseResult.isClose || parseResult.tagName.length === 0) {
        continue;
      }
      const node: HtmlNode = new HtmlNode();
      node.tag = parseResult.tagName;
      node.attributes = parseResult.attributes;
      const parent: HtmlNode = stack[stack.length - 1];
      node.parent = parent;
      parent.children.push(node);
      if (HtmlParser.RAW_TEXT_TAGS.has(node.tag)) {
        const closeMarker: string = `</${node.tag}`;
        const rawStart: number = parseResult.nextIndex;
        let rawEnd: number = html.toLowerCase().indexOf(closeMarker, rawStart);
        if (rawEnd < 0) {
          rawEnd = len;
        }
        const rawText: string = html.substring(rawStart, rawEnd);
        if (rawText.length > 0) {
          const textNode: HtmlNode = new HtmlNode();
          textNode.isText = true;
          textNode.text = rawText;
          textNode.parent = node;
          node.children.push(textNode);
        }
        const closeGt: number = html.indexOf('>', rawEnd);
        i = closeGt < 0 ? len : closeGt + 1;
        continue;
      }
      if (!HtmlParser.VOID_TAGS.has(node.tag) && !parseResult.selfClosing) {
        stack.push(node);
      }
    }
    return root;
  }

  private static appendTextTo(parent: HtmlNode, raw: string): void {
    if (raw.length === 0) {
      return;
    }
    const textNode: HtmlNode = new HtmlNode();
    textNode.isText = true;
    textNode.text = HtmlParser.decodeEntities(raw);
    textNode.parent = parent;
    parent.children.push(textNode);
  }

  private static handleCloseTag(stack: HtmlNode[], closeTag: string): void {
    for (let i = stack.length - 1; i >= 1; i--) {
      if (stack[i].tag === closeTag) {
        stack.length = i;
        return;
      }
    }
  }

  private static parseTag(html: string, startIndex: number): TagParseResult {
    const result: TagParseResult = new TagParseResult();
    const len: number = html.length;
    let i: number = startIndex + 1;
    let nameStart: number = i;
    while (i < len && /[^\s/>]/.exec(html.charAt(i)) !== null) {
      i++;
    }
    if (i >= len) {
      result.nextIndex = -1;
      return result;
    }
    result.tagName = html.substring(nameStart, i).toLowerCase();
    while (i < len) {
      while (i < len && /\s/.exec(html.charAt(i)) !== null) {
        i++;
      }
      if (i >= len) {
        result.nextIndex = -1;
        return result;
      }
      if (html.charAt(i) === '>') {
        result.nextIndex = i + 1;
        return result;
      }
      if (html.charAt(i) === '/') {
        i++;
        if (i < len && html.charAt(i) === '>') {
          result.selfClosing = true;
          result.nextIndex = i + 1;
          return result;
        }
        continue;
      }
      let attrStart: number = i;
      while (i < len && /[^\s=/>]/.exec(html.charAt(i)) !== null) {
        i++;
      }
      if (i === attrStart) {
        i++;
        continue;
      }
      const attrName: string = html.substring(attrStart, i).toLowerCase();
      let attrValue: string = '';
      let hasValue: boolean = false;
      let scan: number = i;
      while (scan < len && /\s/.exec(html.charAt(scan)) !== null) {
        scan++;
      }
      if (scan < len && html.charAt(scan) === '=') {
        scan++;
        while (scan < len && /\s/.exec(html.charAt(scan)) !== null) {
          scan++;
        }
        if (scan < len && (html.charAt(scan) === '"' || html.charAt(scan) === '\'')) {
          const quote: string = html.charAt(scan);
          const valueEnd: number = html.indexOf(quote, scan + 1);
          if (valueEnd < 0) {
            attrValue = html.substring(scan + 1);
            i = len;
            hasValue = true;
          } else {
            attrValue = html.substring(scan + 1, valueEnd);
            i = valueEnd + 1;
            hasValue = true;
          }
        } else {
          const valueStart: number = scan;
          while (scan < len && /[^\s>]/.exec(html.charAt(scan)) !== null) {
            scan++;
          }
          attrValue = html.substring(valueStart, scan);
          i = scan;
          hasValue = true;
        }
      }
      if (attrName.length > 0) {
        result.attributes.set(attrName, hasValue ? HtmlParser.decodeEntities(attrValue) : '');
      }
    }
    result.nextIndex = -1;
    return result;
  }

  static decodeEntities(input: string): string {
    if (input.indexOf('&') < 0) {
      return input;
    }
    let out: string = '';
    let i: number = 0;
    const len: number = input.length;
    while (i < len) {
      const ch: string = input.charAt(i);
      if (ch !== '&') {
        out += ch;
        i++;
        continue;
      }
      const semi: number = input.indexOf(';', i + 1);
      if (semi < 0 || semi - i > 12) {
        out += ch;
        i++;
        continue;
      }
      const entity: string = input.substring(i + 1, semi);
      let decoded: string = '';
      if (entity.length > 1 && entity.charAt(0) === '#') {
        let code: number = -1;
        if (entity.charAt(1) === 'x' || entity.charAt(1) === 'X') {
          code = Number.parseInt(entity.substring(2), 16);
        } else {
          code = Number.parseInt(entity.substring(1), 10);
        }
        if (!Number.isNaN(code) && code >= 0 && code <= 0x10FFFF) {
          decoded = String.fromCodePoint(code);
        }
      } else {
        const named: string | undefined = HtmlParser.namedEntity(entity);
        decoded = named !== undefined ? named : '';
      }
      if (decoded.length > 0) {
        out += decoded;
        i = semi + 1;
      } else {
        out += ch;
        i++;
      }
    }
    return out;
  }

  private static namedEntity(name: string): string | undefined {
    if (name === 'amp') {
      return '&';
    }
    if (name === 'lt') {
      return '<';
    }
    if (name === 'gt') {
      return '>';
    }
    if (name === 'quot') {
      return '"';
    }
    if (name === 'apos') {
      return '\'';
    }
    if (name === 'nbsp') {
      return ' ';
    }
    if (name === 'mdash') {
      return '—';
    }
    if (name === 'ndash') {
      return '–';
    }
    if (name === 'hellip') {
      return '…';
    }
    if (name === 'copy') {
      return '©';
    }
    if (name === 'middot') {
      return '·';
    }
    return undefined;
  }

  // ==================== 查询 API ====================

  static getElementById(root: HtmlNode, id: string): HtmlNode | null {
    const found: HtmlNode[] = HtmlParser.querySelectorAll(root, `#${id}`);
    return found.length > 0 ? found[0] : null;
  }

  static getElementsByTagName(root: HtmlNode, tag: string): HtmlNode[] {
    return HtmlParser.querySelectorAll(root, tag);
  }

  static getElementsByClassName(root: HtmlNode, className: string): HtmlNode[] {
    return HtmlParser.querySelectorAll(root, `.${className}`);
  }

  /**
   * 选择器子集：逗号分组；组内空格为后代组合器；
   * 简单选择器：tag / * / #id / .class / [attr] / [attr=value]（值可带引号），可组合如 input[name=lt].w#x。
   */
  static querySelectorAll(root: HtmlNode, selector: string): HtmlNode[] {
    const results: HtmlNode[] = [];
    const groups: string[] = selector.split(',');
    for (let g = 0; g < groups.length; g++) {
      const group: string = groups[g].trim();
      if (group.length === 0) {
        continue;
      }
      const parts: string[] = group.split(/\s+/);
      const simples: SimpleSelector[] = [];
      for (let p = 0; p < parts.length; p++) {
        const simple: SimpleSelector | null = HtmlParser.parseSimpleSelector(parts[p]);
        if (simple !== null) {
          simples.push(simple);
        }
      }
      if (simples.length === 0) {
        continue;
      }
      HtmlParser.collectMatches(root, simples, simples.length - 1, results);
    }
    return results;
  }

  static querySelector(root: HtmlNode, selector: string): HtmlNode | null {
    const found: HtmlNode[] = HtmlParser.querySelectorAll(root, selector);
    return found.length > 0 ? found[0] : null;
  }

  private static collectMatches(node: HtmlNode, simples: SimpleSelector[], index: number, results: HtmlNode[]): void {
    for (let i = 0; i < node.children.length; i++) {
      const child: HtmlNode = node.children[i];
      if (!child.isElement()) {
        continue;
      }
      if (simples[index].matches(child)) {
        if (index === 0) {
          results.push(child);
        } else if (HtmlParser.hasAncestorMatching(child, simples, index - 1)) {
          results.push(child);
        }
      }
      HtmlParser.collectMatches(child, simples, index, results);
    }
  }

  private static hasAncestorMatching(start: HtmlNode, simples: SimpleSelector[], index: number): boolean {
    let ancestor: HtmlNode | null = start.parent;
    while (ancestor !== null && ancestor.isElement()) {
      if (simples[index].matches(ancestor)) {
        if (index === 0) {
          return true;
        }
        if (HtmlParser.hasAncestorMatching(ancestor, simples, index - 1)) {
          return true;
        }
      }
      ancestor = ancestor.parent;
    }
    return false;
  }

  private static parseSimpleSelector(part: string): SimpleSelector | null {
    if (part.length === 0) {
      return null;
    }
    const simple: SimpleSelector = new SimpleSelector();
    let i: number = 0;
    const len: number = part.length;
    let nameStart: number = -1;
    for (; i <= len; i++) {
      const isBoundary: boolean = i === len || part.charAt(i) === '#' || part.charAt(i) === '.'
        || part.charAt(i) === '[';
      if (!isBoundary) {
        if (nameStart < 0) {
          nameStart = i;
        }
        continue;
      }
      if (nameStart >= 0) {
        simple.tag = part.substring(nameStart, i).toLowerCase();
        nameStart = -1;
      }
      if (i === len) {
        break;
      }
      const marker: string = part.charAt(i);
      if (marker === '#') {
        const end: number = HtmlParser.scanUntil(part, i + 1, '#.[');
        simple.id = part.substring(i + 1, end);
        i = end - 1;
      } else if (marker === '.') {
        const end: number = HtmlParser.scanUntil(part, i + 1, '#.[');
        simple.classes.push(part.substring(i + 1, end));
        i = end - 1;
      } else if (marker === '[') {
        const end: number = part.indexOf(']', i);
        if (end < 0) {
          return simple;
        }
        const inner: string = part.substring(i + 1, end).trim();
        const eq: number = inner.indexOf('=');
        if (eq < 0) {
          simple.attrName = inner.toLowerCase();
          simple.attrMustMatchValue = false;
        } else {
          simple.attrName = inner.substring(0, eq).trim().toLowerCase();
          let value: string = inner.substring(eq + 1).trim();
          if (value.length >= 2 && (value.startsWith('"') || value.startsWith('\''))
            && value.endsWith(value.charAt(0))) {
            value = value.substring(1, value.length - 1);
          }
          simple.attrValue = value;
          simple.attrMustMatchValue = true;
        }
        i = end;
      }
    }
    if (simple.tag.length === 0 && simple.id.length === 0 && simple.classes.length === 0
      && simple.attrName.length === 0) {
      return null;
    }
    return simple;
  }

  private static scanUntil(text: string, from: number, stops: string): number {
    let i: number = from;
    while (i < text.length && stops.indexOf(text.charAt(i)) < 0) {
      i++;
    }
    return i;
  }
}

class TagParseResult {
  tagName: string = '';
  attributes: Map<string, string> = new Map();
  selfClosing: boolean = false;
  isClose: boolean = false;
  nextIndex: number = -1;
}
