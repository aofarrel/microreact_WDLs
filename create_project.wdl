version 1.0

workflow Microreact_Create_Workspace {
	input {
		File token
		File mr_template_json
		Boolean verbose        = true
		Int max_python_retries = 0
		Int max_wdl_retries    = 0
	}

	call mr_create {
		input:
			token = token,
			mr_template_json = mr_template_json,
			verbose = verbose,
			max_python_retries = max_python_retries,
			max_wdl_retries = max_wdl_retries
	}

	output {
		String new_workspace_uri = mr_create.new_workspace_uri
	}
}

task mr_create {
	input {
		File token
		File mr_template_json
		Boolean verbose
		Int max_python_retries
		Int max_wdl_retries
	}
	
	command <<<
		set -eu pipefail
		set +x
		python3 << CODE
		import requests
		import time
		import json

		# https://github.com/openwdl/wdl/blob/legacy/versions/1.0/SPEC.md#true-and-false
		verbose = bool(~{true='True' false='False' verbose})
		assert type(verbose) == bool

		with open("~{token}", 'r', encoding="utf-8") as file:
			TOKEN_STR = file.readline().strip()

		def debug_print(response):
			print(f"[DEBUG] Status code: {response.status_code}")
			print(f"[DEBUG] Response body: {response.text!r}")
			print(f"[DEBUG] Response headers: {dict(response.headers)}")
			return

		def wait(retries):
			if ~{max_python_retries} - retries == 1:
				print("WAITING ONE MINUTE, THEN RETRYING...")
				time.sleep(60)
			elif ~{max_python_retries} - retries <= 0:
				return
			else:
				print("WAITING TWO SECONDS, THEN RETRYING...")
				time.sleep(2)

		with open("~{mr_template_json}", "r", encoding="utf-8") as temp_proj_json:
			payload = json.load(temp_proj_json)

		def create_new_mr_project(token, payload, retries=-1): # returns new URL
			if retries < ~{max_python_retries}:
				try:
					response = requests.post("https://microreact.org/api/projects/create",
						headers={"Access-Token": token, "Content-Type": "application/json; charset=UTF-8"},
						params={"access": "private"},
						timeout=120,
						json=payload)
					if verbose:
						debug_print(response)
					if response.status_code == 200:
						URL = response.json()['id']
						return URL
					print(f"Failed to create new MR project [code {response.status_code}]: {response.text}")
					retries =+ 1
					wait(retries)
					create_new_mr_project(token, payload, retries)
				except Exception as e: # ignore: broad-exception-caught
					print(f"Caught exception trying to create new MR project: {e}")
					retries =+ 1
					wait(retries)
					create_new_mr_project(token, payload, retries)
			else:
				print(f"Failed to create MR project after ~{max_python_retries} retries. Something's broken.")
				exit(1)

		uri = create_new_mr_project(TOKEN_STR, payload)
		with open("uri.txt", "w", encoding="utf-8") as outfile:
			outfile.write(uri)

		CODE

	>>>

	runtime {
		cpu: 2
		disks: "local-disk 10 HDD"
		docker: "ashedpotatoes/dropkick:0.0.2"
		memory: "8 GB"
		preemptible: 2
		maxRetries: max_wdl_retries
	}

	output {
		String new_workspace_uri = read_string("uri.txt")
	}
}
