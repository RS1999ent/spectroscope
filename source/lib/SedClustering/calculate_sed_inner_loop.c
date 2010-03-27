/* $cmuPDL: calculate_sed_loop.c, v $ */

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
 * @return: The normalized string-edit distance between both strings
 */
double calculate_nsed(int const * const str1, int const str1_length,
                      int const * const str2, int const str2_length) {

    /* Take care of base cases */
    if (str1_length == 0 && str2_length == 0) {
        return 0;
    }
    if (str1_length == 0 || str2_length == 0) {
        return 1;
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
    int sed_value = calculate_nsed(str1, str1_length, str2, str2_length);

    printf("%d", sed_value);
 }   
