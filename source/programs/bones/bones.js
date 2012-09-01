// Source: Ilmari Heikkinen
// ilmari.heikkinen@gmail.com
// http://fhtr.org/bones_bm/

Vec4 = function() {
  this.f32a = new Float32Array(4);
};

Vec4.prototype.load = function(v, off) {
  this.f32a[0] = v[off+0];
  this.f32a[1] = v[off+1];
  this.f32a[2] = v[off+2];
  this.f32a[3] = v[off+3];
  return this;
};

Vec4.prototype.store = function(v, off) {
  v[off+0] = this.f32a[0];
  v[off+1] = this.f32a[1];
  v[off+2] = this.f32a[2];
  v[off+3] = this.f32a[3];
  return this;
};

Vec4.prototype.set = function(v) {
  this.f32a.set(v.f32a);
  return this;
};

Vec4.prototype.setF = function(v) {
  this.f32a[0] = v;
  this.f32a[1] = v;
  this.f32a[2] = v;
  this.f32a[3] = v;
  return this;
};

Vec4.prototype.addF = function(v) {
  this.f32a[0] += v;
  this.f32a[1] += v;
  this.f32a[2] += v;
  this.f32a[3] += v;
  return this;
};

Vec4.prototype.subF = function(v) {
  this.f32a[0] -= v;
  this.f32a[1] -= v;
  this.f32a[2] -= v;
  this.f32a[3] -= v;
  return this;
};

Vec4.prototype.mulF = function(v) {
  this.f32a[0] *= v;
  this.f32a[1] *= v;
  this.f32a[2] *= v;
  this.f32a[3] *= v;
  return this;
};

Vec4.prototype.divF = function(v) {
  this.f32a[0] /= v;
  this.f32a[1] /= v;
  this.f32a[2] /= v;
  this.f32a[3] /= v;
  return this;
};

Vec4.prototype.add = function(v) {
  this.f32a[0] += v.f32a[0];
  this.f32a[1] += v.f32a[1];
  this.f32a[2] += v.f32a[2];
  this.f32a[3] += v.f32a[3];
  return this;
};

Vec4.prototype.sub = function(v) {
  this.f32a[0] -= v.f32a[0];
  this.f32a[1] -= v.f32a[1];
  this.f32a[2] -= v.f32a[2];
  this.f32a[3] -= v.f32a[3];
  return this;
};

Vec4.prototype.mul = function(v) {
  this.f32a[0] *= v.f32a[0];
  this.f32a[1] *= v.f32a[1];
  this.f32a[2] *= v.f32a[2];
  this.f32a[3] *= v.f32a[3];
  return this;
};

Vec4.prototype.div = function(v) {
  this.f32a[0] /= v.f32a[0];
  this.f32a[1] /= v.f32a[1];
  this.f32a[2] /= v.f32a[2];
  this.f32a[3] /= v.f32a[3];
  return this;
};


Bones = {};

Bones.applyBones_inlined = function(dstVertices, srcVertices, weights, bones) {
  var x,y,z,w,i,k,woff,off,len,wlen,totalWeight,wt,boff,dx,dy,dz,dw;
  for (i = 0, off = 0, len = srcVertices.length; off < len; i++, off += 4) {
    woff = i*5+1;
    wlen = weights[woff-1];
    if (wlen == 0) {
      dstVertices[off] = srcVertices[off];
      dstVertices[off+1] = srcVertices[off+1];
      dstVertices[off+2] = srcVertices[off+2];
      dstVertices[off+3] = srcVertices[off+3];
    } else {
      dx=0.0, dy=0.0, dz=0.0, dw=0.0;
      x = srcVertices[off+0], y = srcVertices[off+1], z = srcVertices[off+2], w = srcVertices[off+3];
      totalWeight = 0.0;
      for (k=0; k < wlen; k++) {
        wt = weights[woff+k*2+1];
        totalWeight += wt;
        boff = 0 | weights[woff+k*2]*16;
        dx += wt * (bones[boff+0] * x + bones[boff+4] * y + bones[boff+8] * z + bones[boff+12] * w);
        dy += wt * (bones[boff+1] * x + bones[boff+5] * y + bones[boff+9] * z + bones[boff+13] * w);
        dz += wt * (bones[boff+2] * x + bones[boff+6] * y + bones[boff+10] * z + bones[boff+14] * w);
        dw += wt * (bones[boff+3] * x + bones[boff+7] * y + bones[boff+11] * z + bones[boff+15] * w);
      }
      dstVertices[off+0] = dx/totalWeight;
      dstVertices[off+1] = dy/totalWeight;
      dstVertices[off+2] = dz/totalWeight;
      dstVertices[off+3] = dw/totalWeight;
    }
  }
};

Bones.applyBones_readable = function(dstVertices, srcVertices, weights, bones) {
  var tmp = new Vec4(), tmp2 = new Vec4(), dv = new Vec4(), sv = new Vec4();
  var i,off,len,woff,totalWeight,k,wlen,wt,boff;
  for (i = 0, off = 0, len = srcVertices.length; off < len; i++, off += 4) {
    woff = i*5+1;
    dv.load(dstVertices, off);
    sv.load(srcVertices, off);
    if (weights[woff-1] == 0) {
      dv.set(sv);
    } else {
      dv.setF(0.0);
      totalWeight = 0.0;
      for (k=0, wlen=weights[woff-1]; k < wlen; k++) {
        wt = weights[woff+k*2+1];
        totalWeight += wt;
        boff = 0 | weights[woff+k*2]*16;
        tmp2.set(tmp.load(bones, boff).mulF(sv.f32a[0]));
        tmp2.add(tmp.load(bones, boff+4).mulF(sv.f32a[1]));
        tmp2.add(tmp.load(bones, boff+8).mulF(sv.f32a[2]));
        tmp2.add(tmp.load(bones, boff+12).mulF(sv.f32a[3]));
        dv.add(tmp2.mulF(wt));
      }
      dv.divF(totalWeight);
    }
    dv.store(dstVertices, off);
  }
};

// pack weights into a {len, boneIdx, weight, boneIdx, weight} flat array
Bones.makeWeights = function(count, boneCount) {
  var weights = new Float32Array(count*5);
  for (var i=0, off=0; i<count; i++, off+5) {
    var len = 0 | (Math.random()+1);
    weights[off] = len;
    for (var j=0; j<len; j++) {
      weights[off+1+j*2] = 0 | (Math.random()*boneCount);
      weights[off+2+j*2] = Math.random();
    }
  }
  return weights;
};

Bones.makeBMArray = function(count, value) {
  var arr = new Float32Array(count*4);
  for (var i=0; i<arr.length; i++) {
    arr[i] = value;
  }
  return arr;
};

Bones.useSSE = false;

Bones.initBenchmark = function(count, boneCount) {
  var bbones = new Float32Array(16*boneCount);

  var weights = this.makeWeights(count, boneCount);
  var srcVertices = this.makeBMArray(count, 1);
  var dstVertices = this.makeBMArray(count, 2);

  Bones.runBenchmark = function() {
    for (var i=0; i<100; i++) {
      if (Bones.useSSE) {
        Bones.applyBones_sse(dstVertices, srcVertices, weights, bbones);
      } else {
        Bones.applyBones_inlined(dstVertices, srcVertices, weights, bbones);
      }
      for (var j=0; j<bbones.length; j+=16) {
        bbones[j] = i;
        bbones[j+1] = i;
        bbones[j+2] = i;
        bbones[j+3] = i;
      }
    }
  };
};


Bones.initBenchmark(1000000, 200);
Bones.runBenchmark();

