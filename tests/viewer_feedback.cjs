// Pure JS checks; no browser automation or input-to-paint timing claim.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { transportButton } = require('../data/viewer-feedback.js');
for (const [width,height,z] of [[1280,720,2],[1440,900,2],[1920,1080,3],[390,844,1]]) {
  const left = Math.floor((width-320*z)/2), top = height-42*z;
  assert.deepEqual(transportButton(width,height,left+45*z,top+12*z),
    { x:left+38*z, y:top+4*z, width:14*z, height:20*z });
  assert.equal(transportButton(width,height,left+45*z,top+27*z),null);
}
let listener, animations = 0;
const flash = {style:{},setAttribute(){},animate(frames,options){
  ++animations;
  assert.equal(options.duration,220);
  return {cancel(){}};
}};
const canvas = {
  addEventListener(type,fn,options){assert.equal(type,'pointerdown');assert(options.capture);listener=fn;},
  getBoundingClientRect(){return {left:0,top:0,width:1280,height:720};}
};
vm.runInNewContext(fs.readFileSync('data/viewer-feedback.js','utf8'),{
  document:{getElementById(){return canvas;},createElement(){return flash;},body:{appendChild(){}}},
  window:{matchMedia(){return {matches:false};}}
});
listener({button:0,clientX:410,clientY:660});
assert.equal(animations,1,'animation starts synchronously with pointerdown');
assert.equal(flash.style.display,'block');
listener({button:0,clientX:600,clientY:300});
assert.equal(animations,1,'map clicks do not flash the transport');
console.log('Transport hit geometry and immediate feedback dispatch passed');
