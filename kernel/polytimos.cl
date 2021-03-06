/* Test kernel implementation.
 *
 * ==========================(LICENSE BEGIN)============================
 *
 * Copyright (c) 2017 tpruvot
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * ===========================(LICENSE END)=============================
 *
 * @author tpruvot 2017
 */
 
#if __ENDIAN_LITTLE__
  #define SPH_LITTLE_ENDIAN 1
#else
  #define SPH_BIG_ENDIAN 1
#endif
 
#define SPH_UPTR sph_u64
typedef unsigned int sph_u32;
typedef int sph_s32;
 
#ifndef __OPENCL_VERSION__
  typedef unsigned long long sph_u64;
#else
  typedef unsigned long sph_u64;
#endif
 
#define SPH_64 1
#define SPH_64_TRUE 1
 
#define SPH_C32(x) ((sph_u32)(x ## U))
#define SPH_T32(x) (as_uint(x))
#define SPH_ROTL32(x, n) rotate(as_uint(x), as_uint(n))
#define SPH_ROTR32(x, n) SPH_ROTL32(x, (32 - (n)))
 
#define SPH_C64(x) ((sph_u64)(x ## UL))
#define SPH_T64(x) (as_ulong(x))
#define SPH_ROTL64(x, n) rotate(as_ulong(x), (n) & 0xFFFFFFFFFFFFFFFFUL)
#define SPH_ROTR64(x, n) SPH_ROTL64(x, (64 - (n)))
 
 
#define SPH_ECHO_64 1
 
#ifndef SPH_LUFFA_PARALLEL
  #define SPH_LUFFA_PARALLEL 0
#endif
 
#include "wolf-skein.cl"
#include "wolf-shabal.cl"
#include "wolf-echo.cl"
#include "wolf-aes.cl"
#include "luffa.cl"
#include "fugue.cl"
#include "streebog.cl"
 
#define SWAP4(x) as_uint(as_uchar4(x).wzyx)
#define SWAP8(x) as_ulong(as_uchar8(x).s76543210)
 
#if SPH_BIG_ENDIAN
  #define DEC64LE(x) SWAP8(*(const __global sph_u64 *) (x));
#else
  #define DEC64LE(x) (*(const __global sph_u64 *) (x));
#endif
 
#define SHL(x, n) ((x) << (n))
#define SHR(x, n) ((x) >> (n))
 
typedef union {
  unsigned char h1[64];
  uint h4[16];
  ulong h8[8];
} hash_t;
 
#define SWAP8_OUTPUT(x)  SWAP8(x)

// skein80 
__attribute__((reqd_work_group_size(WORKSIZE, 1, 1)))
__kernel void search(__global ulong* block, __global hash_t* hashes)
{
  uint gid = get_global_id(0);
  uint offset = get_global_offset(0);
  __global hash_t *hash = &(hashes[gid-offset]);

  ulong8 m = vload8(0, block);

  const ulong8 h = (ulong8)(  0x4903ADFF749C51CEUL, 0x0D95DE399746DF03UL, 0x8FD1934127C79BCEUL, 0x9A255629FF352CB1UL,
                0x5DB62599DF6CA7B0UL, 0xEABE394CA9D5C3F4UL, 0x991112C71A75B523UL, 0xAE18A40B660FCC33UL);

  const ulong t[3] = { 0x40UL, 0x7000000000000000UL, 0x7000000000000040UL },
       t1[3] = { 0x50UL, 0xB000000000000000UL, 0xB000000000000050UL },
       t2[3] = { 0x08UL, 0xFF00000000000000UL, 0xFF00000000000008UL };

  ulong8 p = Skein512Block(m, h, 0xCAB2076D98173EC4UL, t);

  ulong8 h2 = m ^ p;

  m = (ulong8)(block[8], (block[9] & 0x00000000FFFFFFFF) ^ ((ulong)(gid) << 32), 0UL, 0UL, 0UL, 0UL, 0UL, 0UL);
  ulong h8 = h2.s0 ^ h2.s1 ^ h2.s2 ^ h2.s3 ^ h2.s4 ^ h2.s5 ^ h2.s6 ^ h2.s7 ^ SKEIN_KS_PARITY;

  p = Skein512Block(m, h2, h8, t1);

  h2 = m ^ p;

  p = (ulong8)(0);
  h8 = h2.s0 ^ h2.s1 ^ h2.s2 ^ h2.s3 ^ h2.s4 ^ h2.s5 ^ h2.s6 ^ h2.s7 ^ SKEIN_KS_PARITY;

  p = Skein512Block(p, h2, h8, t2);

  vstore8(p, 0, hash->h8);

  barrier(CLK_GLOBAL_MEM_FENCE);
}

// shabal64
__attribute__((reqd_work_group_size(WORKSIZE, 1, 1)))
__kernel void search1(__global hash_t* hashes)
{
  uint gid = get_global_id(0);
  uint offset = get_global_offset(0);
  __global hash_t *hash = &(hashes[gid-offset]);

	// shabal
	uint16 A, B, C, M;
	uint Wlow = 1;
	
	A.s0 = A_init_512[0];
	A.s1 = A_init_512[1];
	A.s2 = A_init_512[2];
	A.s3 = A_init_512[3];
	A.s4 = A_init_512[4];
	A.s5 = A_init_512[5];
	A.s6 = A_init_512[6];
	A.s7 = A_init_512[7];
	A.s8 = A_init_512[8];
	A.s9 = A_init_512[9];
	A.sa = A_init_512[10];
	A.sb = A_init_512[11];
	
	B = vload16(0, B_init_512);
	C = vload16(0, C_init_512);
	M = vload16(0, hash->h4);
	
	// INPUT_BLOCK_ADD
	B += M;
	
	// XOR_W
	//do { A.s0 ^= Wlow; } while(0);
	A.s0 ^= Wlow;
	
	// APPLY_P
	B = rotate(B, 17U);
	SHABAL_PERM_V;
	
	uint16 tmpC1, tmpC2, tmpC3;
	
	tmpC1 = shuffle2(C, (uint16)0, (uint16)(11, 12, 13, 14, 15, 0, 1, 2, 3, 4, 5, 6, 17, 17, 17, 17));
	tmpC2 = shuffle2(C, (uint16)0, (uint16)(15, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 17, 17, 17, 17));
	tmpC3 = shuffle2(C, (uint16)0, (uint16)(3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 17, 17, 17, 17));
	
	A += tmpC1 + tmpC2 + tmpC3;
		
	// INPUT_BLOCK_SUB
	C -= M;
	
	++Wlow;
	M = 0;
	M.s0 = 0x80;
	
	#pragma unroll 2
	for(int i = 0; i < 4; ++i)
	{
		SWAP_BC_V;
		
		// INPUT_BLOCK_ADD
		B.s0 = select(B.s0, B.s0 += M.s0, i==0);
		
		// XOR_W;
		A.s0 ^= Wlow;
		
		// APPLY_P
		B = rotate(B, 17U);
		SHABAL_PERM_V;
		
		if(i == 3) break;
		
		tmpC1 = shuffle2(C, (uint16)0, (uint16)(11, 12, 13, 14, 15, 0, 1, 2, 3, 4, 5, 6, 17, 17, 17, 17));
		tmpC2 = shuffle2(C, (uint16)0, (uint16)(15, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 17, 17, 17, 17));
		tmpC3 = shuffle2(C, (uint16)0, (uint16)(3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 17, 17, 17, 17));
	
		A += tmpC1 + tmpC2 + tmpC3;
	}
	
	vstore16(B, 0, hash->h4);

  barrier(CLK_GLOBAL_MEM_FENCE);
}

// echo64
__attribute__((reqd_work_group_size(WORKSIZE, 1, 1)))
__kernel void search2(__global hash_t* hashes)
{
  uint gid = get_global_id(0);
  uint offset = get_global_offset(0);
  __global hash_t *hash = &(hashes[gid-offset]);

  __local uint AES0[256];
  for(int i = get_local_id(0), step = get_local_size(0); i < 256; i += step)
    AES0[i] = AES0_C[i];

  uint4 W[16];

  // Precomp
  W[0] = (uint4)(0xe7e9f5f5, 0xf5e7e9f5, 0xb3b36b23, 0xb3dbe7af);
  W[1] = (uint4)(0x14b8a457, 0xf5e7e9f5, 0xb3b36b23, 0xb3dbe7af);
  W[2] = (uint4)(0xdbfde1dd, 0xf5e7e9f5, 0xb3b36b23, 0xb3dbe7af);
  W[3] = (uint4)(0x9ac2dea3, 0xf5e7e9f5, 0xb3b36b23, 0xb3dbe7af);
  W[4] = (uint4)(0x65978b09, 0xf5e7e9f5, 0xb3b36b23, 0xb3dbe7af);
  W[5] = (uint4)(0xa4213d7e, 0xf5e7e9f5, 0xb3b36b23, 0xb3dbe7af);
  W[6] = (uint4)(0x265f4382, 0xf5e7e9f5, 0xb3b36b23, 0xb3dbe7af);
  W[7] = (uint4)(0x34514d9e, 0xf5e7e9f5, 0xb3b36b23, 0xb3dbe7af);
  W[12] = (uint4)(0xb134347e, 0xea6f7e7e, 0xbd7731bd, 0x8a8a1968);
  W[13] = (uint4)(0x579f9f33, 0xfbfbfbfb, 0xfbfbfbfb, 0xefefd3c7);
  W[14] = (uint4)(0x2cb6b661, 0x6b23b3b3, 0xcf93a7cf, 0x9d9d3751);
  W[15] = (uint4)(0x01425eb8, 0xf5e7e9f5, 0xb3b36b23, 0xb3dbe7af);

  ((uint16 *)W)[2] = vload16(0, hash->h4);

  barrier(CLK_LOCAL_MEM_FENCE);

  #pragma unroll
	for(int x = 8; x < 12; ++x) {
		uint4 tmp;
		tmp = Echo_AES_Round_Small(AES0, W[x]);
		tmp.s0 ^= x | 0x200;
		W[x] = Echo_AES_Round_Small(AES0, tmp);
	}
  BigShiftRows(W);
  BigMixColumns(W);

  #pragma unroll 1
  for(uint k0 = 16; k0 < 160; k0 += 16) {
      BigSubBytesSmall(AES0, W, k0);
      BigShiftRows(W);
      BigMixColumns(W);
  }

  #pragma unroll
  for(int i = 0; i < 4; ++i)
    vstore4(vload4(i, hash->h4) ^ W[i] ^ W[i + 8] ^ (uint4)(512, 0, 0, 0), i, hash->h4);

  barrier(CLK_GLOBAL_MEM_FENCE);
}
 
__attribute__((reqd_work_group_size(WORKSIZE, 1, 1)))
__kernel void search3(__global hash_t* hashes)
{
  uint gid = get_global_id(0);
  __global hash_t *hash = &(hashes[gid-get_global_offset(0)]);
 
  // luffa
 
  sph_u32 V00 = SPH_C32(0x6d251e69), V01 = SPH_C32(0x44b051e0), V02 = SPH_C32(0x4eaa6fb4), V03 = SPH_C32(0xdbf78465), V04 = SPH_C32(0x6e292011), V05 = SPH_C32(0x90152df4), V06 = SPH_C32(0xee058139), V07 = SPH_C32(0xdef610bb);
  sph_u32 V10 = SPH_C32(0xc3b44b95), V11 = SPH_C32(0xd9d2f256), V12 = SPH_C32(0x70eee9a0), V13 = SPH_C32(0xde099fa3), V14 = SPH_C32(0x5d9b0557), V15 = SPH_C32(0x8fc944b3), V16 = SPH_C32(0xcf1ccf0e), V17 = SPH_C32(0x746cd581);
  sph_u32 V20 = SPH_C32(0xf7efc89d), V21 = SPH_C32(0x5dba5781), V22 = SPH_C32(0x04016ce5), V23 = SPH_C32(0xad659c05), V24 = SPH_C32(0x0306194f), V25 = SPH_C32(0x666d1836), V26 = SPH_C32(0x24aa230a), V27 = SPH_C32(0x8b264ae7);
  sph_u32 V30 = SPH_C32(0x858075d5), V31 = SPH_C32(0x36d79cce), V32 = SPH_C32(0xe571f7d7), V33 = SPH_C32(0x204b1f67), V34 = SPH_C32(0x35870c6a), V35 = SPH_C32(0x57e9e923), V36 = SPH_C32(0x14bcb808), V37 = SPH_C32(0x7cde72ce);
  sph_u32 V40 = SPH_C32(0x6c68e9be), V41 = SPH_C32(0x5ec41e22), V42 = SPH_C32(0xc825b7c7), V43 = SPH_C32(0xaffb4363), V44 = SPH_C32(0xf5df3999), V45 = SPH_C32(0x0fc688f1), V46 = SPH_C32(0xb07224cc), V47 = SPH_C32(0x03e86cea);
 
  DECL_TMP8(M);
 
  M0 = (hash->h4[1]);
  M1 = (hash->h4[0]);
  M2 = (hash->h4[3]);
  M3 = (hash->h4[2]);
  M4 = (hash->h4[5]);
  M5 = (hash->h4[4]);
  M6 = (hash->h4[7]);
  M7 = (hash->h4[6]);
 
  for(uint i = 0; i < 5; i++)
  {
    MI5;
    LUFFA_P5;
 
    if(i == 0)
    {
      M0 = (hash->h4[9]);
      M1 = (hash->h4[8]);
      M2 = (hash->h4[11]);
      M3 = (hash->h4[10]);
      M4 = (hash->h4[13]);
      M5 = (hash->h4[12]);
      M6 = (hash->h4[15]);
      M7 = (hash->h4[14]);
    }
    else if(i == 1)
    {
      M0 = 0x80000000;
      M1 = M2 = M3 = M4 = M5 = M6 = M7 = 0;
    }
    else if(i == 2)
      M0 = M1 = M2 = M3 = M4 = M5 = M6 = M7 = 0;
    else if(i == 3)
    {
      hash->h4[0] = V00 ^ V10 ^ V20 ^ V30 ^ V40;
      hash->h4[1] = V01 ^ V11 ^ V21 ^ V31 ^ V41;
      hash->h4[2] = V02 ^ V12 ^ V22 ^ V32 ^ V42;
      hash->h4[3] = V03 ^ V13 ^ V23 ^ V33 ^ V43;
      hash->h4[4] = V04 ^ V14 ^ V24 ^ V34 ^ V44;
      hash->h4[5] = V05 ^ V15 ^ V25 ^ V35 ^ V45;
      hash->h4[6] = V06 ^ V16 ^ V26 ^ V36 ^ V46;
      hash->h4[7] = V07 ^ V17 ^ V27 ^ V37 ^ V47;
    }
  }
 
  hash->h4[8] = V00 ^ V10 ^ V20 ^ V30 ^ V40;
  hash->h4[9] = V01 ^ V11 ^ V21 ^ V31 ^ V41;
  hash->h4[10] = V02 ^ V12 ^ V22 ^ V32 ^ V42;
  hash->h4[11] = V03 ^ V13 ^ V23 ^ V33 ^ V43;
  hash->h4[12] = V04 ^ V14 ^ V24 ^ V34 ^ V44;
  hash->h4[13] = V05 ^ V15 ^ V25 ^ V35 ^ V45;
  hash->h4[14] = V06 ^ V16 ^ V26 ^ V36 ^ V46;
  hash->h4[15] = V07 ^ V17 ^ V27 ^ V37 ^ V47;
 
  //if (!gid) printf("LUFFA %02x..%02x\n", (uint) hash->h1[0], (uint) hash->h1[31]);
  //if (!gid) printf("LUFFA %02x..%02x\n", (uint) ((uchar*)&M0)[0], (uint) ((uchar*)&M7)[0]);

  barrier(CLK_GLOBAL_MEM_FENCE);
}
 
__attribute__((reqd_work_group_size(WORKSIZE, 1, 1)))
__kernel void search4(__global hash_t* hashes)
{
  uint gid = get_global_id(0);
  uint offset = get_global_offset(0);
  __global hash_t *hash = &(hashes[gid-offset]);
 
  //mixtab
  __local sph_u32 mixtab0[256], mixtab1[256], mixtab2[256], mixtab3[256];
  int init = get_local_id(0);
  int step = get_local_size(0);
  for (int i = init; i < 256; i += step)
  {
    mixtab0[i] = mixtab0_c[i];
    mixtab1[i] = mixtab1_c[i];
    mixtab2[i] = mixtab2_c[i];
    mixtab3[i] = mixtab3_c[i];
  }
  barrier(CLK_GLOBAL_MEM_FENCE);
 
  // fugue
  sph_u32 S00, S01, S02, S03, S04, S05, S06, S07, S08, S09;
  sph_u32 S10, S11, S12, S13, S14, S15, S16, S17, S18, S19;
  sph_u32 S20, S21, S22, S23, S24, S25, S26, S27, S28, S29;
  sph_u32 S30, S31, S32, S33, S34, S35;
 
  ulong fc_bit_count = (sph_u64) 0x200;
 
  S00 = S01 = S02 = S03 = S04 = S05 = S06 = S07 = S08 = S09 = S10 = S11 = S12 = S13 = S14 = S15 = S16 = S17 = S18 = S19 = 0;
  S20 = SPH_C32(0x8807a57e); S21 = SPH_C32(0xe616af75); S22 = SPH_C32(0xc5d3e4db); S23 = SPH_C32(0xac9ab027);
  S24 = SPH_C32(0xd915f117); S25 = SPH_C32(0xb6eecc54); S26 = SPH_C32(0x06e8020b); S27 = SPH_C32(0x4a92efd1);
  S28 = SPH_C32(0xaac6e2c9); S29 = SPH_C32(0xddb21398); S30 = SPH_C32(0xcae65838); S31 = SPH_C32(0x437f203f);
  S32 = SPH_C32(0x25ea78e7); S33 = SPH_C32(0x951fddd6); S34 = SPH_C32(0xda6ed11d); S35 = SPH_C32(0xe13e3567);
 
  FUGUE512_3((hash->h4[0x0]), (hash->h4[0x1]), (hash->h4[0x2]));
  FUGUE512_3((hash->h4[0x3]), (hash->h4[0x4]), (hash->h4[0x5]));
  FUGUE512_3((hash->h4[0x6]), (hash->h4[0x7]), (hash->h4[0x8]));
  FUGUE512_3((hash->h4[0x9]), (hash->h4[0xA]), (hash->h4[0xB]));
  FUGUE512_3((hash->h4[0xC]), (hash->h4[0xD]), (hash->h4[0xE]));
  FUGUE512_3((hash->h4[0xF]), as_uint2(fc_bit_count).y, as_uint2(fc_bit_count).x);
 
  // apply round shift if necessary
  int i;
 
  for (i = 0; i < 32; i ++)
  {
    ROR3;
    CMIX36(S00, S01, S02, S04, S05, S06, S18, S19, S20);
    SMIX(S00, S01, S02, S03);
  }
 
  for (i = 0; i < 13; i ++)
  {
    S04 ^= S00;
    S09 ^= S00;
    S18 ^= S00;
    S27 ^= S00;
    ROR9;
    SMIX(S00, S01, S02, S03);
    S04 ^= S00;
    S10 ^= S00;
    S18 ^= S00;
    S27 ^= S00;
    ROR9;
    SMIX(S00, S01, S02, S03);
    S04 ^= S00;
    S10 ^= S00;
    S19 ^= S00;
    S27 ^= S00;
    ROR9;
    SMIX(S00, S01, S02, S03);
    S04 ^= S00;
    S10 ^= S00;
    S19 ^= S00;
    S28 ^= S00;
    ROR8;
    SMIX(S00, S01, S02, S03);
  }
  S04 ^= S00;
  S09 ^= S00;
  S18 ^= S00;
  S27 ^= S00;
 
  hash->h4[0] = SWAP4(S01);
  hash->h4[1] = SWAP4(S02);
  hash->h4[2] = SWAP4(S03);
  hash->h4[3] = SWAP4(S04);
  hash->h4[4] = SWAP4(S09);
  hash->h4[5] = SWAP4(S10);
  hash->h4[6] = SWAP4(S11);
  hash->h4[7] = SWAP4(S12);
  hash->h4[8] = SWAP4(S18);
  hash->h4[9] = SWAP4(S19);
  hash->h4[10] = SWAP4(S20);
  hash->h4[11] = SWAP4(S21);
  hash->h4[12] = SWAP4(S27);
  hash->h4[13] = SWAP4(S28);
  hash->h4[14] = SWAP4(S29);
  hash->h4[15] = SWAP4(S30);

  barrier(CLK_GLOBAL_MEM_FENCE);
}
__attribute__((reqd_work_group_size(WORKSIZE, 1, 1)))
__kernel void search5(__global hash_t* hashes, __global uint* output, const ulong target)
{
  uint gid = get_global_id(0);
  __global hash_t *hash = &(hashes[gid-get_global_offset(0)]);
 
  // Streebog
 
  __local sph_u64 lT[8][256];
 
  for(int i=0; i<8; i++) {
    for(int j=0; j<256; j++) lT[i][j] = T[i][j];
  }
 
  __local unsigned char lCC[12][64];
  __local void*    vCC[12];
  __local sph_u64* sCC[12];
 
  for(int i=0; i<12; i++) {
    for(int j=0; j<64; j++) lCC[i][j] = CC[i][j];
  }
 
  for(int i=0; i<12; i++) {
    vCC[i] = lCC[i];
  }
  for(int i=0; i<12; i++) {
    sCC[i] = vCC[i];
  }
 
  sph_u64 message[8];
  message[0] = (hash->h8[0]);
  message[1] = (hash->h8[1]);
  message[2] = (hash->h8[2]);
  message[3] = (hash->h8[3]);
  message[4] = (hash->h8[4]);
  message[5] = (hash->h8[5]);
  message[6] = (hash->h8[6]);
  message[7] = (hash->h8[7]);
 
  sph_u64 out[8];
  sph_u64 len = 512;
  GOST_HASH_512(message, len, out);

  //if (!gid) printf("STREEBOG %02x..%02x\n", (uint) hash->h1[0], (uint) hash->h1[31]);
  //if (!gid) printf("STREEBOG %02x..%02x\n", (uint) ((uchar*)out)[0], (uint) ((uchar*)out)[31]);
 
  if (out[3] <= target)
    output[atomic_inc(output+0xFF)] = gid;
}
