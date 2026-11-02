import htmlBranchesNewBranch from 'test_fixtures/branches/new_branch.html';
import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import NewBranchForm from '~/new_branch_form';

describe('Branch', () => {
  let testContext;

  beforeEach(() => {
    testContext = {};
  });

  describe('create a new branch', () => {
    function fillNameWith(value) {
      document.querySelector('.js-branch-name').value = value;
      const event = new CustomEvent('change');
      document.querySelector('.js-branch-name').dispatchEvent(event);
    }

    const findName = () => document.querySelector('.js-branch-name');
    const findError = () => document.querySelector('.js-branch-name-error');

    function expectToHaveError(error) {
      expect(findError().textContent).toEqual(error);
    }

    function submitForm() {
      const event = new Event('submit', { cancelable: true });
      document.querySelector('form').dispatchEvent(event);
      return event;
    }

    beforeEach(() => {
      setHTMLFixture(htmlBranchesNewBranch);
      testContext.form = new NewBranchForm(document.querySelector('.js-create-branch-form'), []);
    });

    afterEach(() => {
      resetHTMLFixture();
    });

    it("can't start with a dot", () => {
      fillNameWith('.foo');
      expectToHaveError("Branch name cannot start with '.'");
    });

    it("can't start with a slash", () => {
      fillNameWith('/foo');
      expectToHaveError("Branch name cannot start with '/'");
    });

    it("can't have two consecutive dots", () => {
      fillNameWith('foo..bar');
      expectToHaveError("Branch name cannot contain '..'");
    });

    it("can't have spaces anywhere", () => {
      fillNameWith(' foo');
      expectToHaveError('Branch name cannot contain spaces');
      fillNameWith('foo bar');
      expectToHaveError('Branch name cannot contain spaces');
      fillNameWith('foo ');
      expectToHaveError('Branch name cannot contain spaces');
    });

    it("can't have ~ anywhere", () => {
      fillNameWith('~foo');
      expectToHaveError("Branch name cannot contain '~'");
      fillNameWith('foo~bar');
      expectToHaveError("Branch name cannot contain '~'");
      fillNameWith('foo~');
      expectToHaveError("Branch name cannot contain '~'");
    });

    it("can't have tilde anwhere", () => {
      fillNameWith('~foo');
      expectToHaveError("Branch name cannot contain '~'");
      fillNameWith('foo~bar');
      expectToHaveError("Branch name cannot contain '~'");
      fillNameWith('foo~');
      expectToHaveError("Branch name cannot contain '~'");
    });

    it("can't have caret anywhere", () => {
      fillNameWith('^foo');
      expectToHaveError("Branch name cannot contain '^'");
      fillNameWith('foo^bar');
      expectToHaveError("Branch name cannot contain '^'");
      fillNameWith('foo^');
      expectToHaveError("Branch name cannot contain '^'");
    });

    it("can't have : anywhere", () => {
      fillNameWith(':foo');
      expectToHaveError("Branch name cannot contain ':'");
      fillNameWith('foo:bar');
      expectToHaveError("Branch name cannot contain ':'");
      fillNameWith(':foo');
      expectToHaveError("Branch name cannot contain ':'");
    });

    it("can't have question mark anywhere", () => {
      fillNameWith('?foo');
      expectToHaveError("Branch name cannot contain '?'");
      fillNameWith('foo?bar');
      expectToHaveError("Branch name cannot contain '?'");
      fillNameWith('foo?');
      expectToHaveError("Branch name cannot contain '?'");
    });

    it("can't have asterisk anywhere", () => {
      fillNameWith('*foo');
      expectToHaveError("Branch name cannot contain '*'");
      fillNameWith('foo*bar');
      expectToHaveError("Branch name cannot contain '*'");
      fillNameWith('foo*');
      expectToHaveError("Branch name cannot contain '*'");
    });

    it("can't have open bracket anywhere", () => {
      fillNameWith('[foo');
      expectToHaveError("Branch name cannot contain '['");
      fillNameWith('foo[bar');
      expectToHaveError("Branch name cannot contain '['");
      fillNameWith('foo[');
      expectToHaveError("Branch name cannot contain '['");
    });

    it("can't have a backslash anywhere", () => {
      fillNameWith('\\foo');
      expectToHaveError("Branch name cannot contain '\\'");
      fillNameWith('foo\\bar');
      expectToHaveError("Branch name cannot contain '\\'");
      fillNameWith('foo\\');
      expectToHaveError("Branch name cannot contain '\\'");
    });

    it('Branch name cannot contain a sequence @{ anywhere', () => {
      fillNameWith('@{foo');
      expectToHaveError("Branch name cannot contain '@{'");
      fillNameWith('foo@{bar');
      expectToHaveError("Branch name cannot contain '@{'");
      fillNameWith('foo@{');
      expectToHaveError("Branch name cannot contain '@{'");
    });

    it("can't have consecutive slashes", () => {
      fillNameWith('foo//bar');
      expectToHaveError('Branch name cannot contain consecutive slashes');
    });

    it("can't end with a slash", () => {
      fillNameWith('foo/');
      expectToHaveError("Branch name cannot end in '/'");
    });

    it("can't end with a dot", () => {
      fillNameWith('foo.');
      expectToHaveError("Branch name cannot end in '.'");
    });

    it("can't end with .lock", () => {
      fillNameWith('foo.lock');
      expectToHaveError("Branch name cannot end in '.lock'");
    });

    it("can't be the single character @", () => {
      fillNameWith('@');
      expectToHaveError("Branch name cannot be '@'");
    });

    it('concatenates all error messages', () => {
      fillNameWith('/foo bar?~.');
      expectToHaveError(
        "Branch name cannot start with '/'. Branch name cannot contain spaces or '?' or '~'. Branch name cannot end in '.'",
      );
    });

    it("doesn't duplicate error messages", () => {
      fillNameWith('?foo?bar?zoo?');
      expectToHaveError("Branch name cannot contain '?'");
    });

    it('removes the error message when is a valid name', () => {
      fillNameWith('foo?bar');

      expect(document.querySelector('.js-branch-name-error').textContent).not.toEqual('');
      fillNameWith('foobar');

      expect(document.querySelector('.js-branch-name-error').textContent).toEqual('');
    });

    it("can't be empty", () => {
      fillNameWith('');
      expectToHaveError('Branch name is required');
    });

    it('turns off native browser validation', () => {
      expect(document.querySelector('form').noValidate).toBe(true);
    });

    describe('when invalid', () => {
      beforeEach(() => {
        fillNameWith('foo bar');
      });

      it('marks the field as invalid and links the error', () => {
        expect(findName().classList).toContain('is-invalid');
        expect(findName().getAttribute('aria-invalid')).toBe('true');
        expect(findName().getAttribute('aria-describedby')).toBe(findError().id);
      });

      it('updates the error while typing and clears it once fixed', () => {
        findName().value = 'foobar';
        findName().dispatchEvent(new Event('input'));

        expectToHaveError('');
        expect(findName().classList).not.toContain('is-invalid');
        expect(findName().hasAttribute('aria-invalid')).toBe(false);
        expect(findName().hasAttribute('aria-describedby')).toBe(false);
      });

      it('does not rewrite an unchanged error while typing', () => {
        const errorText = findError().firstChild;

        findName().value = 'foo bar baz';
        findName().dispatchEvent(new Event('input'));

        expect(findError().firstChild).toBe(errorText);
      });
    });

    it('does not validate while typing before the first error', () => {
      findName().value = 'foo bar';
      findName().dispatchEvent(new Event('input'));

      expectToHaveError('');
    });

    describe('when submitting', () => {
      it.each`
        name         | error
        ${''}        | ${'Branch name is required'}
        ${'foo bar'} | ${'Branch name cannot contain spaces'}
      `('blocks submit and focuses the field when name is "$name"', ({ name, error }) => {
        findName().value = name;
        const event = submitForm();

        expect(event.defaultPrevented).toBe(true);
        expectToHaveError(error);
        expect(document.activeElement).toBe(findName());
      });

      it('allows submit with a valid name', () => {
        findName().value = 'foo';

        expect(submitForm().defaultPrevented).toBe(false);
        expectToHaveError('');
      });
    });

    describe('with a server error', () => {
      beforeEach(() => {
        setHTMLFixture(htmlBranchesNewBranch);
        findName().value = 'master';
        findError().textContent = 'Branch already exists';
        testContext.form = new NewBranchForm(document.querySelector('.js-create-branch-form'));
      });

      it('keeps the server error while the name is unchanged', () => {
        expectToHaveError('Branch already exists');
        expect(findName().getAttribute('aria-invalid')).toBe('true');
      });

      it('clears the server error once the name changes', () => {
        fillNameWith('main');

        expectToHaveError('');
      });

      it('shows a specific client error instead of the server error', () => {
        fillNameWith('foo bar');

        expectToHaveError('Branch name cannot contain spaces');
      });
    });

    it('can have dashes anywhere', () => {
      fillNameWith('-foo-bar-zoo-');

      expect(document.querySelector('.js-branch-name-error').textContent).toEqual('');
    });

    it('can have underscores anywhere', () => {
      fillNameWith('_foo_bar_zoo_');

      expect(document.querySelector('.js-branch-name-error').textContent).toEqual('');
    });

    it('can have numbers anywhere', () => {
      fillNameWith('1foo2bar3zoo4');

      expect(document.querySelector('.js-branch-name-error').textContent).toEqual('');
    });

    it('can be only letters', () => {
      fillNameWith('foo');

      expect(document.querySelector('.js-branch-name-error').textContent).toEqual('');
    });
  });
});
