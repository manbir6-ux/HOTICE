'use strict';
const assert = require('node:assert/strict');
const {moveClip} = require('../public/assets/timeline_core.js');

{
  const a = {id:1}, b={id:2}, c={id:3};
  const clips = [a,b,c];
  const selected = moveClip(clips, 0, 1, 2);
  assert.deepEqual(clips,[b,a,c]);
  assert.equal(selected, 2, 'another clip moved; selected C should remain C');
}
{
  const a={id:'A'}, b={id:'B'}, c={id:'C'};
  const clips = [a,b,c];
  const selected = moveClip(clips, 0, 1, 0);
  assert.deepEqual(clips,[b,a,c]);
  assert.equal(selected,1,'moving selected A follows its new position');
}
{
  const clips=[{id:1},{id:2}];
  assert.equal(moveClip(clips, 1, 1, 0),0,
    'out-of-range movement leaves selection unchanged');
  assert.equal(moveClip(clips, 0, 1, -1),-1,
    'no selection stays unselected');
}
for (const args of [[null,0,1,0], [[], '0', 1, 0]]) {
  assert.throws(()=>moveClip(...args), TypeError);
}
console.log('HOTICE timeline reorder regression tests passed.');
