/* eslint-disable func-names, no-return-assign, @gitlab/require-i18n-strings */
import { __ } from '~/locale';

const NAME_ERROR_CLASS = 'is-invalid';

export default class NewBranchForm {
  constructor(form) {
    this.validate = this.validate.bind(this);
    this.revalidate = this.revalidate.bind(this);
    this.onSubmit = this.onSubmit.bind(this);
    this.form = form;
    this.branchNameError = form.querySelector('.js-branch-name-error');
    this.name = form.querySelector('.js-branch-name');
    this.serverError = this.branchNameError.textContent.trim();
    this.serverErrorName = this.name.value;
    this.setupRestrictions();
    this.addBinding();
    this.init();
  }

  addBinding() {
    this.name.addEventListener('change', this.validate);
    this.name.addEventListener('input', this.revalidate);
    this.form.addEventListener('submit', this.onSubmit);
  }

  init() {
    if (this.name != null && this.name.value.length > 0) {
      const event = new CustomEvent('change');
      this.name.dispatchEvent(event);
    }
  }

  onSubmit(event) {
    if (this.validate()) return;

    event.preventDefault();
    this.name.focus();
  }

  revalidate() {
    if (this.name.getAttribute('aria-invalid') === 'true') this.validate();
  }

  setupRestrictions() {
    const startsWith = {
      pattern: /^(\/|\.)/g,
      prefix: 'Branch name cannot start with',
      conjunction: 'or',
    };
    const endsWith = {
      pattern: /(\/|\.|\.lock)$/g,
      prefix: 'Branch name cannot end in',
      conjunction: 'or',
    };
    const invalid = {
      pattern: /(\s|~|\^|:|\?|\*|\[|\\|\.\.|@\{|\/{2,}){1}/g,
      prefix: 'Branch name cannot contain',
      conjunction: ' or ',
    };
    const single = {
      pattern: /^@+$/g,
      prefix: 'Branch name cannot be',
      conjunction: 'or',
    };
    return (this.restrictions = [startsWith, invalid, endsWith, single]);
  }

  validate() {
    const { indexOf } = [];

    const unique = function (values, value) {
      if (indexOf.call(values, value) === -1) {
        values.push(value);
      }
      return values;
    };
    const formatter = function (values, restriction) {
      const formatted = values.map((value) => {
        switch (false) {
          case !/\s/.test(value):
            return 'spaces';
          case !/\/{2,}/g.test(value):
            return 'consecutive slashes';
          default:
            return `'${value}'`;
        }
      });
      return `${restriction.prefix} ${formatted.join(restriction.conjunction)}`;
    };
    const validator = (errors, restriction) => {
      const matched = this.name.value.match(restriction.pattern);
      if (matched) {
        return errors.concat(formatter(matched.reduce(unique, []), restriction));
      }
      return errors;
    };
    const errors = this.restrictions.reduce(validator, []);
    if (this.name.value.length === 0) {
      errors.push(__('Branch name is required'));
    }

    // Server errors, such as an existing branch, stay until the name changes.
    const serverError = this.name.value === this.serverErrorName ? this.serverError : '';
    this.setError(errors.join('. ') || serverError);
    return errors.length === 0;
  }

  setError(message) {
    // Rewriting the same text makes the assertive live region announce it again.
    if (this.branchNameError.textContent !== message) this.branchNameError.textContent = message;
    this.name.classList.toggle(NAME_ERROR_CLASS, Boolean(message));

    if (message) {
      this.name.setAttribute('aria-invalid', 'true');
      this.name.setAttribute('aria-describedby', this.branchNameError.id);
    } else {
      this.name.removeAttribute('aria-invalid');
      this.name.removeAttribute('aria-describedby');
    }
  }
}
