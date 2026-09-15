/* Read-only ChromeOS EC command-version probe for /dev/cros_fp. */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

struct ec_command {
	uint32_t version;
	uint32_t command;
	uint32_t outsize;
	uint32_t insize;
	uint32_t result;
	uint8_t data[];
} __attribute__((packed));

#define EC_IOCTL_COMMAND _IOWR(0xec, 0, struct ec_command)
#define EC_CMD_GET_CMD_VERSIONS 0x0008
#define EC_CMD_FP_INFO 0x0403

static int transfer(int fd, uint32_t command, uint32_t version,
		    const void *output, uint32_t outsize, uint32_t insize,
		    uint32_t *result, uint8_t *data)
{
	uint8_t buffer[sizeof(struct ec_command) + 1024] = {0};
	struct ec_command *request = (struct ec_command *)buffer;

	request->version = version;
	request->command = command;
	request->outsize = outsize;
	request->insize = insize;
	request->result = UINT32_MAX;
	if (outsize)
		memcpy(request->data, output, outsize);

	int length = ioctl(fd, EC_IOCTL_COMMAND, request);
	*result = request->result;
	if (length > 0 && data)
		memcpy(data, request->data, (size_t)length);
	return length;
}

int main(void)
{
	int fd = open("/dev/cros_fp", O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		perror("open /dev/cros_fp");
		return 1;
	}

	uint16_t fp_info_command = EC_CMD_FP_INFO;
	uint8_t response[1024] = {0};
	uint32_t result;
	int length = transfer(fd, EC_CMD_GET_CMD_VERSIONS, 1,
			      &fp_info_command, sizeof(fp_info_command),
			      sizeof(uint32_t), &result, response);
	if (length != (int)sizeof(uint32_t) || result != 0) {
		fprintf(stderr, "GET_CMD_VERSIONS failed: ioctl=%d errno=%d result=%u\n",
			length, length < 0 ? errno : 0, result);
		close(fd);
		return 1;
	}

	uint32_t mask;
	memcpy(&mask, response, sizeof(mask));
	printf("EC_CMD_FP_INFO version mask: 0x%08x\n", mask);
	for (uint32_t version = 0; version < 32; version++) {
		if (!(mask & (UINT32_C(1) << version)))
			continue;
		length = transfer(fd, EC_CMD_FP_INFO, version, NULL, 0,
				  sizeof(response), &result, response);
		printf("  version %u: response=%d bytes result=%u\n",
		       version, length, result);
	}

	close(fd);
	return 0;
}
