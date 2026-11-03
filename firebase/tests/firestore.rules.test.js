// Security rules tests. Run with `cd firebase && npm ci && npm test` (needs the Firebase CLI and Java).
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc, deleteDoc } = require('firebase/firestore');

let env;

const task = (overrides = {}) => ({
  title: 'Write report', notes: '', status: 'todo', priority: 'medium', dueDate: null,
  ownerId: 'ada', collaboratorIds: ['grace'], memberIds: ['ada', 'grace'], attachments: [],
  createdAt: new Date(), updatedAt: new Date(), updatedBy: 'ada', statusUpdatedAt: new Date(),
  ...overrides,
});

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-taskmanager',
    firestore: { rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') },
  });
});

afterAll(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'tasks/t1'), task()));
});

const db = (uid) => env.authenticatedContext(uid).firestore();

test('members can read, strangers cannot', async () => {
  await assertSucceeds(getDoc(doc(db('grace'), 'tasks/t1')));
  await assertFails(getDoc(doc(db('eve'), 'tasks/t1')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'tasks/t1')));
});

test('create requires the caller to be the owner and a member', async () => {
  await assertSucceeds(setDoc(doc(db('ada'), 'tasks/t2'), task({ collaboratorIds: [], memberIds: ['ada'] })));
  await assertFails(setDoc(doc(db('eve'), 'tasks/t3'), task()));
  await assertFails(setDoc(doc(db('ada'), 'tasks/t4'), task({ memberIds: ['grace'] })));
  // A hidden reader in memberIds who is not a collaborator is rejected.
  await assertFails(setDoc(doc(db('ada'), 'tasks/t5'), task({ memberIds: ['ada', 'grace', 'eve'] })));
});

test('owner can update anything but ownership', async () => {
  await assertSucceeds(updateDoc(doc(db('ada'), 'tasks/t1'), { title: 'New title' }));
  await assertFails(updateDoc(doc(db('ada'), 'tasks/t1'), { ownerId: 'grace' }));
});

test('collaborator may only change status fields', async () => {
  await assertSucceeds(updateDoc(doc(db('grace'), 'tasks/t1'), {
    status: 'done', statusUpdatedAt: new Date(), updatedAt: new Date(), updatedBy: 'grace',
  }));
  await assertFails(updateDoc(doc(db('grace'), 'tasks/t1'), { title: 'Hijacked', updatedBy: 'grace' }));
  await assertFails(updateDoc(doc(db('grace'), 'tasks/t1'), { status: 'done', updatedBy: 'ada' }));
});

test('only the owner can delete', async () => {
  await assertFails(deleteDoc(doc(db('grace'), 'tasks/t1')));
  await assertSucceeds(deleteDoc(doc(db('ada'), 'tasks/t1')));
});

test('users write only their own profile', async () => {
  await assertSucceeds(setDoc(doc(db('ada'), 'users/ada'), { email: 'ada@example.com' }));
  await assertFails(setDoc(doc(db('ada'), 'users/grace'), { email: 'x@example.com' }));
  await assertSucceeds(getDoc(doc(db('grace'), 'users/ada')));
});
