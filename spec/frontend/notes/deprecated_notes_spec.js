/* eslint-disable import-x/no-commonjs, no-new */

import $ from 'jquery';
import MockAdapter from 'axios-mock-adapter';
import htmlPipelineSchedulesEditSnippets from 'test_fixtures/snippets/show.html';
import * as renderGFMModule from '~/behaviors/markdown/render_gfm';
import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import { TEST_HOST } from 'helpers/test_constants';
import waitForPromises from 'helpers/wait_for_promises';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_OK } from '~/lib/utils/http_status';
import * as urlUtility from '~/lib/utils/url_utility';

// These must be imported synchronously because they pull dependencies
// from the DOM.
window.jQuery = $;
require('autosize');
require('~/commons');
const Notes = require('~/deprecated_notes').default;

const NOTES_POST_PATH = /(.*)\/notes\?html=true$/;
let mockAxios;

window.project_uploads_path = `${TEST_HOST}/uploads`;
window.gl = window.gl || {};
gl.utils = gl.utils || {};
gl.utils.disableButtonIfEmptyField = () => {};

describe('Old Notes (~/deprecated_notes.js)', () => {
  beforeEach(() => {
    setHTMLFixture(htmlPipelineSchedulesEditSnippets);

    // Re-declare this here so that test_setup.js#beforeEach() doesn't
    // overwrite it.
    mockAxios = new MockAdapter(axios);

    $.ajax = () => {
      throw new Error('$.ajax should not be called through!');
    };
  });

  afterEach(async () => {
    // The Notes component sets a polling interval. Clear it after every run.
    // Make sure to use jest.runOnlyPendingTimers() instead of runAllTimers().
    jest.clearAllTimers();

    await axios.waitForAll().finally(() => mockAxios.restore());

    // The legacy app leaves its delegated submit handler attached after cleanup.
    $(document).off(
      'click',
      'button.js-comment-submit-button, .js-comment-submit-button > button:first-child',
    );
    resetHTMLFixture();
  });

  describe('initial GFM rendering', () => {
    it('calls renderGFM on the notes list during construction', () => {
      const spy = jest.spyOn(renderGFMModule, 'renderGFM');

      new Notes('', []);

      const notesList = document.getElementById('notes-list');
      expect(notesList).not.toBeNull();
      expect(spy).toHaveBeenCalledWith(notesList);
    });
  });

  describe('GFM rendering on note update', () => {
    it('calls renderGFM after the updated note is in the DOM', () => {
      const notes = new Notes('', []);
      const noteId = 1234;
      const noteHtml = `<li class="note note-row-${noteId} timeline-entry" id="note_${noteId}">
        <div class="note-text">original</div>
      </li>`;

      const notesList = document.getElementById('notes-list');
      notesList.innerHTML = noteHtml;

      const spy = jest.spyOn(renderGFMModule, 'renderGFM').mockImplementation((node) => {
        expect(document.contains(node)).toBe(true);
      });

      notes.updateNote(
        { id: noteId, html: noteHtml.replace('original', 'updated') },
        $(`.note-row-${noteId}`),
      );

      expect(spy).toHaveBeenCalled();
    });
  });

  describe('GFM rendering on cancel edit with pending update', () => {
    it('calls renderGFM after the cached note replaces the original in the DOM', () => {
      const notes = new Notes('', []);
      const noteId = 5678;
      const noteHtml = `<li class="note note-row-${noteId} timeline-entry" id="note_${noteId}" data-note-id="${noteId}">
        <div class="note-text">original</div>
      </li>`;

      const notesList = document.getElementById('notes-list');
      notesList.innerHTML = noteHtml;

      notes.updatedNotesTrackingMap[noteId] = {
        html: noteHtml.replace('original', 'updated from server'),
      };

      const spy = jest.spyOn(renderGFMModule, 'renderGFM').mockImplementation((node) => {
        expect(document.contains(node)).toBe(true);
      });

      const event = $.Event('click');
      event.target = notesList.querySelector('.note');

      notes.cancelEdit(event);

      expect(spy).toHaveBeenCalled();
    });
  });

  describe('legacy notes', () => {
    it('loads the Notes class into the DOM', () => {
      expect(Notes).toBeDefined();
      expect(Notes.name).toBe('Notes');
    });

    describe('addBinding', () => {
      it('calls postComment when comment button is clicked', () => {
        jest.spyOn(Notes.prototype, 'postComment');

        new Notes('', []);
        $('.js-comment-submit-button > button:first-child').click();
        expect(Notes.prototype.postComment).toHaveBeenCalled();
      });
    });

    describe('task lists', () => {
      beforeEach(() => {
        mockAxios.onAny().reply(HTTP_STATUS_OK, {});
        new Notes('', []);
      });

      it('modifies the Markdown field', () => {
        const changeEvent = document.createEvent('HTMLEvents');
        changeEvent.initEvent('change', true, true);
        $('input[type=checkbox]').attr('checked', true)[0].dispatchEvent(changeEvent);

        expect($('.js-task-list-field.original-task-list').val()).toBe('- [x] Task List Item');
      });

      it('submits the updated task when a checkbox changes', () => {
        jest.spyOn(axios, 'patch');

        const { updateUrl } = document.querySelector(
          '.js-task-list-field.original-task-list',
        ).dataset;
        const checkbox = document.querySelector('.task-list-item-checkbox');
        checkbox.checked = true;
        checkbox.dispatchEvent(new Event('change', { bubbles: true }));

        expect(axios.patch).toHaveBeenCalledWith(updateUrl, {
          note: {
            note: '- [x] Task List Item',
            lock_version: undefined,
            update_task: {
              checked: true,
              line_source: '- [ ] Task List Item',
              line_sourcepos: '1:4-1:4',
            },
          },
        });
      });
    });

    describe('comments', () => {
      let notes;
      let textarea;

      beforeEach(() => {
        notes = new Notes('', []);
        textarea = $('.js-main-target-form .js-note-text');
      });

      it('autosizes after comment submission', async () => {
        mockAxios.onPost(NOTES_POST_PATH).reply(HTTP_STATUS_OK, {});
        const autosizeSpy = jest.fn();
        textarea.on('autosize:update', autosizeSpy);
        textarea.val('This is an example comment note');

        await notes.postComment({
          preventDefault: jest.fn(),
          target: document.querySelector('.js-comment-submit-button > button:first-child'),
        });

        expect(autosizeSpy).toHaveBeenCalled();
      });

      it('preserves unescaped comment text when posting fails', async () => {
        mockAxios.onPost(NOTES_POST_PATH).networkError();
        textarea.val('A comment with <markup> & `code`.');

        await notes.postComment({
          preventDefault: jest.fn(),
          target: document.querySelector('.js-comment-submit-button > button:first-child'),
        });

        expect(textarea.val()).toBe('A comment with <markup> & `code`.');
      });
    });

    describe('updateNote', () => {
      let notes;
      let noteEntity;
      let $notesContainer;

      beforeEach(() => {
        notes = new Notes('', []);
        window.gon.current_username = 'root';
        window.gon.current_user_fullname = 'Administrator';
        const sampleComment = 'foo';
        noteEntity = {
          id: 1234,
          html: `<li class="note note-row-1234 timeline-entry" id="note_1234">
                  <div class="note-text">${sampleComment}</div>
                  </li>`,
          note: sampleComment,
          valid: true,
        };

        $notesContainer = $('ul.main-notes-list');
        const $form = $('form.js-main-target-form');
        $form.find('textarea.js-note-text').val(sampleComment);

        mockAxios.onPost(NOTES_POST_PATH).reply(HTTP_STATUS_OK, noteEntity);
      });

      it('updates note and resets edit form', async () => {
        jest.spyOn(notes, 'revertNoteEditForm');
        jest.spyOn(notes, 'setupNewNote');

        $('.js-comment-submit-button > button:first-child').click();
        await waitForPromises();

        const $targetNote = $notesContainer.find(`#note_${noteEntity.id}`);
        const updatedNote = { ...noteEntity };
        updatedNote.note = 'bar';
        notes.updateNote(updatedNote, $targetNote);

        expect(notes.revertNoteEditForm).toHaveBeenCalledWith($targetNote);
        expect(notes.setupNewNote).toHaveBeenCalled();
      });
    });

    describe('updateNoteTargetSelector', () => {
      const hash = 'note_foo';
      let $note;

      beforeEach(() => {
        $note = $(`<div id="${hash}"></div>`);
        jest.spyOn($note, 'filter');
        jest.spyOn($note, 'toggleClass');
      });

      // urlUtility is a dependency of the notes module. Its getLocatinHash() method should be called internally.

      it('sets target when hash matches', () => {
        jest.spyOn(urlUtility, 'getLocationHash').mockReturnValueOnce(hash);

        Notes.updateNoteTargetSelector($note);

        expect(urlUtility.getLocationHash).toHaveBeenCalled();
        expect($note.filter).toHaveBeenCalledWith(`#${hash}`);
        expect($note.toggleClass).toHaveBeenCalledWith('target', true);
      });

      it('unsets target when hash does not match', () => {
        jest.spyOn(urlUtility, 'getLocationHash').mockReturnValueOnce('note_doesnotexist');

        Notes.updateNoteTargetSelector($note);

        expect(urlUtility.getLocationHash).toHaveBeenCalled();
        expect($note.toggleClass).toHaveBeenCalledWith('target', false);
      });

      it('unsets target when there is not a hash fragment anymore', () => {
        jest.spyOn(urlUtility, 'getLocationHash').mockReturnValueOnce(null);

        Notes.updateNoteTargetSelector($note);

        expect(urlUtility.getLocationHash).toHaveBeenCalled();
        expect($note.toggleClass).toHaveBeenCalledWith('target', false);
      });
    });

    describe('renderNote', () => {
      let notes;
      let note;
      let $notesList;

      beforeEach(() => {
        note = {
          id: 1,
          valid: true,
          note: 'heya',
          html: '<div>heya</div>',
        };
        $notesList = {
          find: jest.fn(() => $()),
          append: jest.fn(),
        };
        notes = {
          setupNewNote: jest.fn(),
          refresh: jest.fn(),
          updateNotesCount: jest.fn(),
          putConflictEditWarningInPlace: jest.fn(),
        };
        notes.taskList = {
          init: jest.fn(),
        };
        notes.note_ids = [];
        notes.updatedNotesTrackingMap = {};

        jest.spyOn(Notes, 'isNewNote');
        jest.spyOn(Notes, 'isUpdatedNote');
        jest.spyOn(Notes, 'animateAppendNote');
        jest.spyOn(Notes, 'animateUpdateNote');
      });

      describe('when adding note', () => {
        it('should call .animateAppendNote', () => {
          Notes.isNewNote.mockReturnValueOnce(true);
          Notes.prototype.renderNote.call(notes, note, null, $notesList);

          expect(Notes.animateAppendNote).toHaveBeenCalledWith(note.html, $notesList);
        });
      });

      describe('when note was edited', () => {
        it('should call .animateUpdateNote', () => {
          Notes.isNewNote.mockReturnValueOnce(false);
          Notes.isUpdatedNote.mockReturnValueOnce(true);
          const $note = $('<div>');
          $notesList.find.mockReturnValueOnce($note);
          const $newNote = $(note.html);
          Notes.animateUpdateNote.mockReturnValueOnce($newNote);

          Notes.prototype.renderNote.call(notes, note, null, $notesList);

          expect(Notes.animateUpdateNote).toHaveBeenCalledWith(note.html, $note);
          expect(notes.setupNewNote).toHaveBeenCalledWith($newNote);
        });

        describe('while editing', () => {
          it('should update textarea if nothing has been touched', () => {
            Notes.isNewNote.mockReturnValueOnce(false);
            Notes.isUpdatedNote.mockReturnValueOnce(true);
            const $note = $(`<div class="is-editing">
              <div class="original-note-content">initial</div>
              <textarea class="js-note-text">initial</textarea>
            </div>`);
            $notesList.find.mockReturnValueOnce($note);
            Notes.prototype.renderNote.call(notes, note, null, $notesList);

            expect($note.find('.js-note-text').val()).toEqual(note.note);
          });

          it('should call .putConflictEditWarningInPlace', () => {
            Notes.isNewNote.mockReturnValueOnce(false);
            Notes.isUpdatedNote.mockReturnValueOnce(true);
            const $note = $(`<div class="is-editing">
              <div class="original-note-content">initial</div>
              <textarea class="js-note-text">different</textarea>
            </div>`);
            $notesList.find.mockReturnValueOnce($note);
            Notes.prototype.renderNote.call(notes, note, null, $notesList);

            expect(notes.putConflictEditWarningInPlace).toHaveBeenCalledWith(note, $note);
          });
        });
      });
    });

    describe('isUpdatedNote', () => {
      it('should consider same note text as the same', () => {
        const result = Notes.isUpdatedNote(
          {
            note: 'initial',
          },
          $(`<div>
            <div class="original-note-content">initial</div>
          </div>`),
        );

        expect(result).toEqual(false);
      });

      it('should consider same note with trailing newline as the same', () => {
        const result = Notes.isUpdatedNote(
          {
            note: 'initial\n',
          },
          $(`<div>
            <div class="original-note-content">initial\n</div>
          </div>`),
        );

        expect(result).toEqual(false);
      });

      it('should consider different notes as different', () => {
        const result = Notes.isUpdatedNote(
          {
            note: 'foo',
          },
          $(`<div>
            <div class="original-note-content">bar</div>
          </div>`),
        );

        expect(result).toEqual(true);
      });
    });

    describe('renderDiscussionNote', () => {
      let discussionContainer;
      let note;
      let notes;
      let $form;
      let row;

      beforeEach(() => {
        note = {
          html: '<li></li>',
          discussion_html: '<div></div>',
          discussion_id: 1,
          discussion_resolvable: false,
          diff_discussion_html: false,
        };
        $form = {
          closest: jest.fn(),
          find: jest.fn(),
        };
        $form.length = 1;
        row = {
          prevAll: jest.fn(),
          first: jest.fn(),
          find: jest.fn(),
        };

        notes = {
          isParallelView: jest.fn(),
          updateNotesCount: jest.fn(),
        };
        notes.note_ids = [];

        jest.spyOn(Notes, 'isNewNote');
        jest.spyOn(Notes, 'animateAppendNote').mockImplementation();
        Notes.isNewNote.mockReturnValue(true);
        notes.isParallelView.mockReturnValue(false);
        row.prevAll.mockReturnValue(row);
        row.first.mockReturnValue(row);
        row.find.mockReturnValue(row);
      });

      describe('Discussion root note', () => {
        let body;

        beforeEach(() => {
          body = {
            attr: jest.fn(),
          };
          discussionContainer = { length: 0 };

          $form.closest.mockReturnValueOnce(row).mockReturnValue($form);
          $form.find.mockReturnValue(discussionContainer);
          body.attr.mockReturnValue('');
        });

        it('should call Notes.animateAppendNote', () => {
          Notes.prototype.renderDiscussionNote.call(notes, note, $form);

          expect(Notes.animateAppendNote).toHaveBeenCalledWith(
            note.discussion_html,
            $('.main-notes-list'),
          );
        });

        describe('HTML output', () => {
          let line;

          beforeEach(() => {
            $form.length = 0;
            note.discussion_line_code = 'line_code';
            note.diff_discussion_html = '<tr class="notes_holder"></tr>';

            line = document.createElement('div');
            line.id = note.discussion_line_code;
            document.body.appendChild(line);

            // Override mocks for these tests
            $form.closest.mockReset();
            $form.closest.mockReturnValue($form);
          });

          it('should append to row selected with line_code', () => {
            Notes.prototype.renderDiscussionNote.call(notes, note, $form);

            expect(line.nextSibling.outerHTML).toEqual(note.diff_discussion_html);
          });

          it('sanitizes the output html without stripping leading <tr> or <td> elements', () => {
            const sanitizedDiscussion =
              '<tr class="notes_holder"><td><a>I am a dolphin!</a></td></tr>';
            note.diff_discussion_html =
              '<tr class="notes_holder"><td><a href="javascript:alert(1)">I am a dolphin!</a></td></tr>';

            Notes.prototype.renderDiscussionNote.call(notes, note, $form);

            expect(line.nextSibling.outerHTML).toEqual(sanitizedDiscussion);
          });
        });
      });

      describe('Discussion sub note', () => {
        beforeEach(() => {
          discussionContainer = { length: 1 };

          $form.closest.mockReturnValueOnce(row).mockReturnValueOnce($form);
          $form.find.mockReturnValue(discussionContainer);

          Notes.prototype.renderDiscussionNote.call(notes, note, $form);
        });

        it('should call Notes.animateAppendNote', () => {
          expect(Notes.animateAppendNote).toHaveBeenCalledWith(note.html, discussionContainer);
        });
      });
    });

    describe('animateAppendNote', () => {
      let noteHTML;
      let $notesList;
      let $resultantNote;

      beforeEach(() => {
        noteHTML = '<div></div>';
        $notesList = {
          find: jest.fn(() => $()),
          append: jest.fn(),
        };

        $resultantNote = Notes.animateAppendNote(noteHTML, $notesList);
      });

      it('should have `fade-in-full` class', () => {
        expect($resultantNote.hasClass('fade-in-full')).toEqual(true);
      });

      it('should append note to the notes list', () => {
        expect($notesList.append).toHaveBeenCalledWith($resultantNote);
      });
    });

    describe('animateUpdateNote', () => {
      let noteHTML;
      let $note;
      let $updatedNote;

      beforeEach(() => {
        noteHTML = '<div></div>';
        $note = {
          replaceWith: jest.fn(),
        };

        $updatedNote = Notes.animateUpdateNote(noteHTML, $note);
      });

      it('should have `fade-in` class', () => {
        expect($updatedNote.hasClass('fade-in')).toEqual(true);
      });

      it('should call replaceWith on $note', () => {
        expect($note.replaceWith).toHaveBeenCalledWith($updatedNote);
      });
    });

    describe('putEditFormInPlace', () => {
      it('passes autocomplete options to the edit form', () => {
        const notes = new Notes('', [], undefined, { emojis: false });
        const $el = $(`
          <div>
            <form></form>
          </div>
        `);

        notes.putEditFormInPlace($el);

        expect(notes.glForm.enableGFM.emojis).toBe(false);
      });
    });

    describe('postComment & updateComment', () => {
      const sampleComment = 'foo';
      const note = {
        id: 1234,
        html: `<li class="note note-row-1234 timeline-entry" id="note_1234">
                <div class="note-text">${sampleComment}</div>
                </li>`,
        note: sampleComment,
        valid: true,
      };
      let notes;
      let $form;
      let $notesContainer;

      function mockNotesPost() {
        mockAxios.onPost(NOTES_POST_PATH).reply(HTTP_STATUS_OK, note);
      }

      function mockNotesPostError() {
        mockAxios.onPost(NOTES_POST_PATH).networkError();
      }

      beforeEach(() => {
        notes = new Notes('', []);
        window.gon.current_username = 'root';
        window.gon.current_user_fullname = 'Administrator';
        $form = $('form.js-main-target-form');
        $notesContainer = $('ul.main-notes-list');
        $form.find('textarea.js-note-text').val(sampleComment);
      });

      it('should show placeholder note while new comment is being posted', () => {
        mockNotesPost();

        $('.js-comment-submit-button > button:first-child').click();

        expect($notesContainer.find('.note.being-posted').length).toBeGreaterThan(0);
      });

      it('should remove placeholder note when new comment is done posting', async () => {
        mockNotesPost();

        $('.js-comment-submit-button > button:first-child').click();

        await waitForPromises();

        expect($notesContainer.find('.note.being-posted')).toHaveLength(0);
      });

      describe('postComment', () => {
        it('disables the submit button', async () => {
          const $submitButton = $form.find('.js-comment-submit-button');

          expect($submitButton).not.toBeDisabled();
          const dummyEvent = {
            preventDefault() {},
            target: $submitButton,
          };
          mockAxios.onPost(NOTES_POST_PATH).replyOnce(() => {
            expect($submitButton).toBeDisabled();
            return [HTTP_STATUS_OK, note];
          });

          await notes.postComment(dummyEvent);
          expect($submitButton).not.toBeDisabled();
        });
      });

      it('should show actual note element when new comment is done posting', async () => {
        mockNotesPost();

        $('.js-comment-submit-button > button:first-child').click();

        await waitForPromises();

        expect($notesContainer.find(`#note_${note.id}`).length).toBeGreaterThan(0);
      });

      it('should reset Form when new comment is done posting', async () => {
        mockNotesPost();

        $('.js-comment-submit-button > button:first-child').click();

        await waitForPromises();

        expect($form.find('textarea.js-note-text').val()).toEqual('');
      });

      it('shows an error alert when a comment fails to post', async () => {
        mockNotesPostError();

        $('.js-comment-submit-button > button:first-child').click();

        await waitForPromises();

        expect(notes.parentTimeline.find('.gl-alert').text()).toContain(
          'Your comment could not be submitted!',
        );
      });
    });

    describe('postComment with quick actions', () => {
      const sampleComment = '/assign @root\n/award :100:';
      const note = {
        commands_changes: {
          assignee_id: 1,
          emoji_award: '100',
        },
        quick_actions_status: {
          messages: 'Commands applied',
        },
        valid: false,
      };
      let $form;
      let $notesContainer;

      beforeEach(() => {
        mockAxios.onPost(NOTES_POST_PATH).reply(HTTP_STATUS_OK, note);

        new Notes('', []);
        window.gon.current_username = 'root';
        window.gon.current_user_fullname = 'Administrator';
        gl.awardsHandler = {
          addAwardToEmojiBar: () => {},
          scrollToAwards: () => {},
        };
        gl.GfmAutoComplete = {
          dataSources: {
            commands: '/root/test-project/autocomplete_sources/commands',
          },
        };
        $form = $('form.js-main-target-form');
        $notesContainer = $('ul.main-notes-list');
        $form
          .find('textarea.js-note-text')
          .attr('data-supports-quick-actions', 'true')
          .val(sampleComment);
      });

      it('should remove quick action placeholder when comment with quick actions is done posting', async () => {
        jest.spyOn(gl.awardsHandler, 'addAwardToEmojiBar');
        $('.js-comment-submit-button > button:first-child').click();

        expect($notesContainer.find('.system-note.being-posted')).toHaveLength(1);

        await waitForPromises();

        expect($notesContainer.find('.system-note.being-posted')).toHaveLength(0);
      });
    });

    describe('postComment with slash when quick actions are not supported', () => {
      const sampleComment = '/assign @root';
      let $form;
      let $notesContainer;

      beforeEach(() => {
        const note = {
          id: 1234,
          html: `<li class="note note-row-1234 timeline-entry" id="note_1234">
                  <div class="note-text">${sampleComment}</div>
                  </li>`,
          note: sampleComment,
          valid: true,
        };
        mockAxios.onPost(NOTES_POST_PATH).reply(HTTP_STATUS_OK, note);

        new Notes('', []);
        $form = $('form.js-main-target-form');
        $notesContainer = $('ul.main-notes-list');
        $form.find('textarea.js-note-text').val(sampleComment);
      });

      it('should show message placeholder including lines starting with slash', async () => {
        $('.js-comment-submit-button > button:first-child').click();

        expect($notesContainer.find('.note.being-posted')).toHaveLength(1); // Placeholder shown
        expect($notesContainer.find('.note-body p').text()).toEqual(sampleComment); // No quick action processing

        await waitForPromises();

        expect($notesContainer.find('.note.being-posted')).toHaveLength(0); // Placeholder removed
      });
    });

    describe('update comment with script tags', () => {
      it('escapes script tags while the edited comment is being saved', async () => {
        mockAxios.onPost(NOTES_POST_PATH).networkError();
        const notes = new Notes('', []);
        const $editButton = $('.js-note-edit').first();
        const $note = $editButton.closest('.note');

        $editButton.click();
        const $textarea = $note.find('textarea.js-note-text');
        expect($textarea).toHaveLength(1);
        $textarea.val('<script>alert(1)</script>');

        notes.updateComment({
          preventDefault: jest.fn(),
          target: $note.find('.js-comment-save-button')[0],
        });

        const $noteText = $note.find('.js-task-list-container .note-text');
        expect($noteText.text()).toBe('<script>alert(1)</script>');
        expect($noteText.find('script')).toHaveLength(0);

        await waitForPromises();
      });
    });

    describe('getFormData', () => {
      let $form;
      let sampleComment;
      let notes;

      beforeEach(() => {
        notes = new Notes('', []);

        $form = $('form');
        sampleComment = 'foobar';
      });

      it('should return form metadata object from form reference', () => {
        $form.find('textarea.js-note-text').val(sampleComment);
        const { formData, formContent, formAction } = notes.getFormData($form);

        expect(formData.indexOf(sampleComment)).toBeGreaterThan(-1);
        expect(formContent).toEqual(sampleComment);
        expect(formAction).toEqual($form.attr('action'));
      });

      it('should return form metadata with sanitized formContent from form reference', () => {
        sampleComment = '<script>alert("Boom!");</script>';
        $form.find('textarea.js-note-text').val(sampleComment);

        const { formContent } = notes.getFormData($form);

        expect(formContent).toEqual('&lt;script&gt;alert(&quot;Boom!&quot;);&lt;/script&gt;');
      });

      it('serializes form data correctly', () => {
        $form.find('textarea.js-note-text').val('hello world&foo=bar');
        $form.append('<input name="other" value="test" />');
        const { formData } = notes.getFormData($form);

        expect(formData).toContain('note%5Bnote%5D=hello+world%26foo%3Dbar');
        expect(formData).toContain('other=test');
      });
    });

    describe('hasQuickActions', () => {
      let notes;

      beforeEach(() => {
        notes = new Notes('', []);
      });

      it('should return true when comment begins with a quick action', () => {
        const sampleComment = '/wip\n/milestone %1.0\n/merge\n/unassign Merging this';
        const hasQuickActions = notes.hasQuickActions(sampleComment);

        expect(hasQuickActions).toBe(true);
      });

      it('should return false when comment does NOT begin with a quick action', () => {
        const sampleComment = 'Hey, /unassign Merging this';
        const hasQuickActions = notes.hasQuickActions(sampleComment);

        expect(hasQuickActions).toBe(false);
      });

      it('should return false when comment does NOT have any quick actions', () => {
        const sampleComment = 'Looking good, Awesome!';
        const hasQuickActions = notes.hasQuickActions(sampleComment);

        expect(hasQuickActions).toBe(false);
      });
    });

    describe('stripQuickActions', () => {
      it('should strip quick actions from the comment which begins with a quick action', () => {
        const notes = new Notes();
        const sampleComment = '/wip\n/milestone %1.0\n/merge\n/unassign Merging this';
        const stripedComment = notes.stripQuickActions(sampleComment);

        expect(stripedComment).toBe('');
      });

      it('should strip quick actions from the comment but leaves plain comment if it is present', () => {
        const notes = new Notes();
        const sampleComment = '/wip\n/milestone %1.0\n/merge\n/unassign\nMerging this';
        const stripedComment = notes.stripQuickActions(sampleComment);

        expect(stripedComment).toBe('Merging this');
      });

      it('should NOT strip string that has slashes within', () => {
        const notes = new Notes();
        const sampleComment = 'http://127.0.0.1:3000/root/gitlab-shell/issues/1';
        const stripedComment = notes.stripQuickActions(sampleComment);

        expect(stripedComment).toBe(sampleComment);
      });
    });

    describe('getQuickActionDescription', () => {
      const availableQuickActions = [
        { name: 'close', description: 'Close this issue', params: [] },
        { name: 'title', description: 'Change title', params: [{}] },
        { name: 'estimate', description: 'Set time estimate', params: [{}] },
      ];
      let notes;

      beforeEach(() => {
        notes = new Notes();
      });

      it('should return executing quick action description when note has single quick action', () => {
        const sampleComment = '/close';

        expect(notes.getQuickActionDescription(sampleComment, availableQuickActions)).toBe(
          'Applying command to close this issue',
        );
      });

      it('should return generic multiple quick action description when note has multiple quick actions', () => {
        const sampleComment = '/close\n/title [Duplicate] Issue foobar';

        expect(notes.getQuickActionDescription(sampleComment, availableQuickActions)).toBe(
          'Applying multiple commands',
        );
      });

      it('should return generic quick action description when available quick actions list is not populated', () => {
        const sampleComment = '/close\n/title [Duplicate] Issue foobar';

        expect(notes.getQuickActionDescription(sampleComment)).toBe('Applying command');
      });
    });

    describe('createPlaceholderNote', () => {
      const sampleComment = 'foobar';
      const uniqueId = 'b1234-a4567';
      const currentUsername = 'root';
      const currentUserFullname = 'Administrator';
      const currentUserAvatar = 'avatar_url';
      let notes;

      beforeEach(() => {
        notes = new Notes('', []);
      });

      it('should return constructed placeholder element for regular note based on form contents', () => {
        const $tempNote = notes.createPlaceholderNote({
          formContent: sampleComment,
          uniqueId,
          isDiscussionNote: false,
          currentUsername,
          currentUserFullname,
          currentUserAvatar,
        });
        const $tempNoteHeader = $tempNote.find('.note-header');

        expect($tempNote.prop('nodeName')).toEqual('LI');
        expect($tempNote.attr('id')).toEqual(uniqueId);
        expect($tempNote.hasClass('being-posted')).toBe(true);
        expect($tempNote.hasClass('fade-in-half')).toBe(true);
        $tempNote.find('.timeline-icon > a, .note-header-info > a').each((i, el) => {
          expect(el.getAttribute('href')).toEqual(`/${currentUsername}`);
        });

        expect($tempNote.find('.timeline-icon .avatar').attr('src')).toEqual(currentUserAvatar);
        expect($tempNote.find('.timeline-content').hasClass('discussion')).toBe(false);
        expect($tempNoteHeader.find('[class~="@sm/panel:gl-inline-block"]').text().trim()).toEqual(
          currentUserFullname,
        );

        expect($tempNoteHeader.find('.note-headline-light').text().trim()).toEqual(
          `@${currentUsername}`,
        );

        expect($tempNote.find('.note-body .note-text p').text().trim()).toEqual(sampleComment);
      });

      it('should return constructed placeholder element for discussion note based on form contents', () => {
        const $tempNote = notes.createPlaceholderNote({
          formContent: sampleComment,
          uniqueId,
          isDiscussionNote: true,
          currentUsername,
          currentUserFullname,
        });

        expect($tempNote.prop('nodeName')).toEqual('LI');
        expect($tempNote.find('.timeline-content').hasClass('discussion')).toBe(true);
      });

      it('should return a escaped user name', () => {
        const currentUserFullnameXSS = 'Foo <script>alert("XSS")</script>';
        const $tempNote = notes.createPlaceholderNote({
          formContent: sampleComment,
          uniqueId,
          isDiscussionNote: false,
          currentUsername,
          currentUserFullname: currentUserFullnameXSS,
          currentUserAvatar,
        });
        const $tempNoteHeader = $tempNote.find('.note-header');

        expect($tempNoteHeader.find('[class~="@sm/panel:gl-inline-block"]').text().trim()).toEqual(
          'Foo &lt;script&gt;alert(&quot;XSS&quot;)&lt;/script&gt;',
        );
      });
    });

    describe('createPlaceholderSystemNote', () => {
      const sampleCommandDescription = 'Applying command to close this issue';
      const uniqueId = 'b1234-a4567';
      let notes;

      beforeEach(() => {
        notes = new Notes('', []);
      });

      it('should return constructed placeholder element for system note based on form contents', () => {
        const $tempNote = notes.createPlaceholderSystemNote({
          formContent: sampleCommandDescription,
          uniqueId,
        });

        expect($tempNote.prop('nodeName')).toEqual('LI');
        expect($tempNote.attr('id')).toEqual(uniqueId);
        expect($tempNote.hasClass('being-posted')).toBe(true);
        expect($tempNote.hasClass('fade-in-half')).toBe(true);
        expect($tempNote.find('.timeline-content i').text().trim()).toEqual(
          sampleCommandDescription,
        );
      });
    });

    describe('addAlert', () => {
      it('shows an error alert', () => {
        const notes = new Notes('', []);
        notes.addAlert({ message: 'Error message', parent: notes.parentTimeline.get(0) });

        expect(notes.parentTimeline.find('.gl-alert').text()).toContain('Error message');
      });
    });

    describe('clearAlert', () => {
      it('removes the alert', () => {
        const notes = new Notes('', []);
        notes.addAlert({ message: 'Error message', parent: notes.parentTimeline.get(0) });

        notes.clearAlert();

        expect(notes.parentTimeline.find('.gl-alert')).toHaveLength(0);
      });
    });
  });
});
