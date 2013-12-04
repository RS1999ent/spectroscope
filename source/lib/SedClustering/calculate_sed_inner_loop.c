/*
 * Copyright (c) 2013, Carnegie Mellon University.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT
 * HOLDERS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
 * OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
 * AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
 * WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

/* $cmuPDL: calculate_sed_inner_loop.c,v 1.1 2010/03/27 04:15:48 rajas Exp $ */

#include <stdio.h>
#include <stdlib.h>

/**
 * Calculates the minimum of 3 values
 *
 * int a: The first value
 * int b: The 2nd value
 * int c: The third value
 *
 * @return: The minimum of 3 values
 */
static inline int minimum(int a, int b, int c) {

    int min = (a < b)? a : b;
    min = (min < c)? min : c;

    return min;
}
    

/**
 * Actually computes the string-edit distance between str1 and str2
 *
 * str1: A int * pointer containing elements of the first string
 * str1_length: The # of elements in the first string
 * str2: A int * pointer containing elements of the second string
 * str2_length: The # of elements in the second string
 *
 * @return: The string-edit distance between both strings
 */
double calculate_sed(int const * const str1, int const str1_length,
                      int const * const str2, int const str2_length) {

    /* Take care of base cases */
    if (str1_length == 0 && str2_length == 0) {
        return 0;
    }
    if (str1_length == 0 || str2_length == 0) {
        return (str1_length == 0)? str2_length : str1_length;
    }

    int *d = malloc((sizeof(int))*(str1_length + 1)*(str2_length + 1));

    for (int i = 0; i <= str1_length; i++) {
        d[i*(str2_length+1)] = i;
    }
    for (int j = 0; j <= str2_length; j++) {
        d[j] = j;
    }

    for (int i = 1; i <= str1_length; i++) {
        for (int j = 1; j <= str2_length; j++) {

            if (str1[i-1] == str2[j-1]) {
                d[i*(str2_length+1) + j] = d[(i-1)*(str2_length+1) + j-1];
            } else {
                d[i*(str2_length+1) + j] = minimum(d[(i-1) * (str2_length + 1) + j] + 1,
                                                   d[i * (str2_length + 1) + j-1] + 1,
                                                   d[(i-1) * (str2_length + 1) + j-1] + 1);
            }
        }
    }

    return d[(str1_length+1) * (str2_length + 1) - 1];
}


/**
 * Retrieves strings for which SeD should be computed from stdin
 * Two strings, comprised of whitespace seperated integers are expected.  A '-1'
 * demarcates the end of the first string and the start of the second
 *
 * @param str1: This will be filled in with the elements of the first string
 * @param str1_length: This will be set to the # of elements in the first string
 * @param str2: This will be filled in with the elements of the second string
 * @param str2_length: This will be set to the # of elements in the 2nd string
 */
void get_input( int * const str1, int * const str1_length,
                int * const str2, int * const str2_length) {
    FILE *instream;
    int *curr_str;
    int *curr_str_length;
    int node_num;
    
    instream = fopen("/dev/stdin", "r");
    curr_str = str1;
    curr_str_length = str1_length;
    *curr_str_length = 0;
    
    while (fscanf(instream, "%d", &node_num) != -1) {
        if (node_num == -1) {
            curr_str = str2;
            curr_str_length = str2_length;
            *curr_str_length = 0;
            continue;
        }

        curr_str[*curr_str_length] = node_num;
        (*curr_str_length)++;
    }
    fclose(instream);
}        


int main () {
    int str1[10000];
    int str1_length;
    int str2[10000];
    int str2_length;
    
    get_input(str1, &str1_length, str2, &str2_length);
    int sed_value = calculate_sed(str1, str1_length, str2, str2_length);

    printf("%d", sed_value);
 }   
