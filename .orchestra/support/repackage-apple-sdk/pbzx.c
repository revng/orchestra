

#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>

// Changelog:
// 02/17/2016 - Fixed so it works with Apple TV OTA PBZX
// 07/28/2016 - Fixed to handle uncompressed chunks and integrate XZ (via liblzma)
// 03/09/2016 - Fixed for single chunks (payload.0##) files, e.g. WatchOS


// To compile: gcc pbzx.c 02_decompress.c -o pbzx -llzma
// On Linux, make sure to install xz-devel first

typedef unsigned long long uint64_t;
typedef unsigned int uint32_t;

#define PBZX_MAGIC	"pbzx"


// This is in 02_decompress.c, modified from liblzma's examples
// I intentionally left that external since it's not my code.

extern void 	decompressXZChunkToStdout(char *buf, int length);



int main(int argc, const char * argv[])
{

    // Dumps a pbzx to stdout. Can work as a filter if no argument is specified

    char buffer[1024];
    int fd = 0;
    int minChunk = 0;

    if (argc < 2) { fd  = 0 ;}
    else { fd = open (argv[1], O_RDONLY);
           if (fd < 0) { perror (argv[1]); exit(5); }
         }

    if (argc ==3) {
	minChunk = atoi(argv[2]);
	fprintf(stderr,"Starting from Chunk %d\n", minChunk);

	}

    read (fd, buffer, 4);
    if (memcmp(buffer, PBZX_MAGIC, 4)) { fprintf(stderr, "Can't find pbzx magic\n"); exit(0);}

    // Now, if it IS a pbzx

    uint64_t length = 0, flags = 0;

    read (fd, &flags, sizeof (uint64_t));
    flags = __builtin_bswap64(flags);

    fprintf(stderr,"Flags: 0x%llx\n", flags);

    int i = 0;
    int off = 0;

    int warn = 0 ;
    int skipChunk = 0;

    int rc = 0;
    // 03/09/2016 - Fixed for single chunks (payload.0##) files, e.g. WatchOS
    //              and for multiple chunks. AAPL changed flags on me..
    //
    // New OTAs use 0x800000 for more chunks, not 0x01000000.

    while (flags &  (0x800000 |  0x01000000)) { // have more chunks
    i++;
    rc= read (fd, &flags, sizeof (uint64_t)); // check retval..
    flags = __builtin_bswap64(flags);
    rc = read (fd, &length, sizeof (uint64_t));
    length = __builtin_bswap64(length);

    skipChunk = (i < minChunk);
    fprintf(stderr,"Chunk #%d (flags: %llx, length: %lld bytes) %s\n",i, flags,length,
     skipChunk? "(skipped)":"");



    // Let's ignore the fact I'm allocating based on user input, etc..
    char *buf = malloc (length);

    int bytes = read (fd, buf, length);
    int totalBytes = bytes;

    // 6/18/2017 - Fix for WatchOS 4.x OTA wherein the chunks are bigger than what can be read in one operation
    while (totalBytes < length) {
		// could be partial read
		bytes = read (fd, buf +totalBytes, length -totalBytes);
		totalBytes +=bytes;
	}



   // We want the XZ header/footer if it's the payload, but prepare_payload doesn't have that,
    // so just warn.

    if (memcmp(buf, "\xfd""7zXZ", 6))  { warn++;
		fprintf (stderr, "Warning: Can't find XZ header. Instead have 0x%x(?).. This is likely not XZ data.\n",
			(* (uint32_t *) buf ));

		// Treat as uncompressed
        	write (1, buf, length);


		}
    else // if we have the header, we had better have a footer, too
	{
    if (strncmp(buf + length - 2, "YZ", 2)) { warn++; fprintf (stderr, "Warning: Can't find XZ footer at 0x%llx (instead have %x). This is bad.\n",
		(length -2),
		*((unsigned short *) (buf + length - 2)));
		}
	if (1 && !skipChunk)
	{
	// Uncompress chunk

	decompressXZChunkToStdout(buf, length);

	}
	warn = 0;

	free (buf);  // Thanks ryandesign (again :-)
	}

    }

    return 0;
}
