// JSDOM doesn't implement `ariaNotify`. Specs assert on calls, not on live regions.
Element.prototype.ariaNotify = jest.fn();
Document.prototype.ariaNotify = jest.fn();
