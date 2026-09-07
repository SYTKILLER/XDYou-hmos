import abilityTest from './Ability.test';
import htmlParserTest from './HtmlParser.test';
import netUtilTest from './NetUtil.test';
import cryptoCharsetTest from './CryptoCharset.test';

export default function testsuite() {
  abilityTest();
  htmlParserTest();
  netUtilTest();
  cryptoCharsetTest();
}
