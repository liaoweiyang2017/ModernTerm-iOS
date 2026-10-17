// ParentNode.replaceChildren arrived after stock Android 10 WebView 74.
// Use DOM text nodes, never innerHTML, when callers provide strings.
(function () {
  [Element.prototype, DocumentFragment.prototype, Document.prototype].forEach(function (prototype) {
    if (typeof prototype.replaceChildren === 'function') return;
    Object.defineProperty(prototype, 'replaceChildren', {
      configurable: true,
      writable: true,
      value: function () {
        var document = this.ownerDocument || this;
        var fragment = document.createDocumentFragment();
        for (var i = 0; i < arguments.length; i++) {
          var child = arguments[i];
          fragment.appendChild(child instanceof Node ? child : document.createTextNode(String(child)));
        }
        while (this.firstChild) this.removeChild(this.firstChild);
        this.appendChild(fragment);
      }
    });
  });
})();
