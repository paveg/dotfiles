FROM amazonlinux:latest

ENV HOME /root

RUN yum update -y && yum install -y zsh util-linux-user
RUN chsh -s /usr/bin/zsh
ENV SHELL /usr/bin/zsh

RUN yum install -y git tar unzip
RUN curl https://mise.run | sh
RUN echo 'eval "$(~/.local/bin/mise activate zsh)"' >> $HOME/.zshrc
RUN $HOME/.local/bin/mise use -g go@latest
RUN $HOME/.local/bin/mise install -y ghq && $HOME/.local/bin/mise use ghq
RUN git config --global ghq.root $HOME/repos

RUN $HOME/.local/share/mise/installs/ghq/latest/bin/ghq get https://github.com/paveg/dotfiles
WORKDIR $HOME/repos/github.com/paveg/dotfiles
RUN git checkout remotes/origin/linux
RUN BUSINESS_USE=1 ./install.sh
WORKDIR $HOME

CMD ["/usr/bin/zsh"]
